// Compatibility shim for AION 2 (NCGuard) under Wine + Rosetta on Apple Silicon.
// Injected into Wine with DYLD_INSERT_LIBRARIES; wraps Wine's fault handlers.
// Build: clang -arch x86_64 -dynamiclib -O1 -Wall -o ncgate.dylib ncgate.c
//
// NCGuard builds this stub to run one CPUID in a 32-bit code segment (cs 0x23):
//   push rbx,rbp,rdi,rsi,r12-r15; mov [r8],rsp; push ss; push rdx; pushfq; push [rcx+8]; push [rcx]; iretq
//   (+0x20) pop r15-r12,rsi,rdi,rbp,rbx; ret
// The iretq target is eip 0xfffffffe = "cpuid"; eip then wraps to 0 and faults, and NCGuard's
// exception handler resumes at +0x20 with rsp = [r8].
// Selector 0x23 is a code segment on Windows and Linux but not on macOS, so Rosetta raises SIGILL at
// the stub's first byte before anything ran; NCGuard then resumes with rsp = 0 and the game hangs.
// We reproduce what Windows would deliver: an execute fault at 0 in cs 0x23, after the cpuid.
#define _XOPEN_SOURCE 700
#define _DARWIN_C_SOURCE
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <pthread.h>
#include <sys/ucontext.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>

static struct sigaction orig[NSIG];
static int logfd = -1;      // set only when SIGDIAG_DIR is given (debug logging)
static int active = 0;      // only in the AION2.exe process
static int trace_left = 0;  // log this many faults after a gate event

static int safe_read(uint64_t addr, void *buf, size_t len)
{
    mach_vm_size_t got = 0;
    return mach_vm_read_overwrite(mach_task_self(), addr, len, (mach_vm_address_t)buf, &got) == KERN_SUCCESS && got == len;
}

static void logf_(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void logf_(const char *fmt, ...)
{
    if (logfd < 0) return;
    char line[900]; va_list ap; va_start(ap, fmt);
    int n = vsnprintf(line, sizeof(line), fmt, ap); va_end(ap);
    if (n > (int)sizeof(line)) n = sizeof(line);
    write(logfd, line, n);
}

static void hexdump(const char *tag, uint64_t addr, size_t len)
{
    unsigned char b[128]; char hex[2 * sizeof(b) + 1] = "";
    if (logfd < 0) return;
    if (len > sizeof(b)) len = sizeof(b);
    int ok = safe_read(addr, b, len);
    for (size_t i = 0; ok && i < len; i++) snprintf(hex + 2 * i, 3, "%02x", b[i]);
    logf_("  %s @%llx ok=%d: %s\n", tag, addr, ok, hex);
}

static void log_ctx(const char *tag, int sig, ucontext_t *uc)
{
    _STRUCT_X86_THREAD_STATE64 *ss = &uc->uc_mcontext->__ss;
    _STRUCT_X86_EXCEPTION_STATE64 *es = &uc->uc_mcontext->__es;
    uint64_t tid = 0; pthread_threadid_np(NULL, &tid);
    logf_("%s sig=%d tid=%llu rip=%llx cs=%llx rsp=%llx rax=%llx rbx=%llx rcx=%llx rdx=%llx r8=%llx fl=%llx trap=%x err=%x fault=%llx\n",
          tag, sig, tid, ss->__rip, ss->__cs, ss->__rsp, ss->__rax, ss->__rbx, ss->__rcx, ss->__rdx, ss->__r8,
          ss->__rflags, es->__trapno, es->__err, es->__faultvaddr);
}

static const unsigned char gate_stub[] = {
    0x53,0x55,0x57,0x56,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57,   // push rbx,rbp,rdi,rsi,r12,r13,r14,r15
    0x49,0x89,0x20,                                                 // mov [r8],rsp
    0x66,0x8c,0xd0,0x50,0x52,0x9c,                                  // mov ax,ss; push rax; push rdx; pushfq
    0x48,0x8b,0x41,0x08,0x50,0x48,0x8b,0x01,0x50,0x48,0xcf,         // push [rcx+8]; push [rcx]; iretq
    0x41,0x5f,0x41,0x5e,0x41,0x5d,0x41,0x5c,0x5e,0x5f,0x5d,0x5b,0xc3 };

// Returns 1 if the context was rewritten into "execute fault at 0 in cs 0x23".
static int emulate_gate(ucontext_t *uc)
{
    _STRUCT_X86_THREAD_STATE64 *ss = &uc->uc_mcontext->__ss;
    _STRUCT_X86_EXCEPTION_STATE64 *es = &uc->uc_mcontext->__es;
    unsigned char b[sizeof(gate_stub)], op[2];
    uint64_t tgt[2], probe;
    if (!safe_read(ss->__rip, b, sizeof(b)) || memcmp(b, gate_stub, sizeof(b))) return 0;
    if (!safe_read(ss->__rcx, tgt, sizeof(tgt))) return 0;
    if (tgt[0] != 0xfffffffe || tgt[1] != 0x23) return 0;                         // only the one known target
    if (!safe_read(tgt[0], op, 2) || op[0] != 0x0f || op[1] != 0xa2) return 0;     // which must be cpuid
    if (!safe_read(ss->__rsp - 64, &probe, 8) || !safe_read(ss->__r8, &probe, 8)) return 0;

    log_ctx("GATE", SIGILL, uc);
    hexdump("newstack", ss->__rdx, 32);
    hexdump("oldstack", ss->__rsp, 64);

    uint64_t *sp = (uint64_t *)ss->__rsp;
    *--sp = ss->__rbx; *--sp = ss->__rbp; *--sp = ss->__rdi; *--sp = ss->__rsi;
    *--sp = ss->__r12; *--sp = ss->__r13; *--sp = ss->__r14; *--sp = ss->__r15;
    *(uint64_t *)ss->__r8 = (uint64_t)sp;

    uint32_t a = (uint32_t)tgt[0], bx = 0, c = (uint32_t)ss->__rcx, d = 0;   // rax was loaded from [rcx]
    uint64_t new_rsp = ss->__rdx;
    __asm__ volatile("cpuid" : "+a"(a), "+b"(bx), "+c"(c), "+d"(d));
    ss->__rax = a; ss->__rbx = bx; ss->__rcx = c; ss->__rdx = d;
    ss->__rsp = new_rsp;
    ss->__rip = 0;            // 0xfffffffe + 2, wrapped to 32 bits
    ss->__cs = tgt[1];
    es->__trapno = 14;        // page fault
    es->__err = 0x14;         // user-mode instruction fetch, page not present
    es->__faultvaddr = 0;
    return 1;
}

static void call_orig(int sig, siginfo_t *si, void *uc)
{
    if (orig[sig].sa_flags & SA_SIGINFO) orig[sig].sa_sigaction(sig, si, uc);
    else if (orig[sig].sa_handler != SIG_DFL && orig[sig].sa_handler != SIG_IGN) orig[sig].sa_handler(sig);
}

static void wrapper(int sig, siginfo_t *si, void *uc_)
{
    ucontext_t *uc = uc_;
    if (sig == SIGILL && uc && uc->uc_mcontext)
    {
        uint64_t cs = uc->uc_mcontext->__ss.__cs;
        if (emulate_gate(uc))
        {
            siginfo_t si2 = *si;
            si2.si_signo = SIGSEGV; si2.si_code = SEGV_MAPERR; si2.si_addr = 0;
            trace_left = 40;
            log_ctx("GATE-deliver", SIGSEGV, uc);
            call_orig(SIGSEGV, &si2, uc);
            if (uc->uc_mcontext->__ss.__cs != cs) uc->uc_mcontext->__ss.__cs = cs;  // never sigreturn into 0x23
            log_ctx("GATE-return", SIGSEGV, uc);
            return;
        }
    }
    if (trace_left > 0 && uc && uc->uc_mcontext)
    {
        trace_left--;
        log_ctx("fault", sig, uc);
        if (sig != SIGBUS) hexdump("code", uc->uc_mcontext->__ss.__rip, 32);
    }
    call_orig(sig, si, uc_);
}

static int my_sigaction(int sig, const struct sigaction *act, struct sigaction *old)
{
    if (active && act && (sig == SIGSEGV || sig == SIGBUS || sig == SIGILL) && (act->sa_flags & SA_SIGINFO))
    {
        struct sigaction mine = *act;
        if (old) *old = orig[sig];
        orig[sig] = *act;
        mine.sa_sigaction = wrapper;
        return sigaction(sig, &mine, NULL);
    }
    return sigaction(sig, act, old);
}

__attribute__((used, section("__DATA,__interpose")))
static struct { void *n, *o; } interposers[] = { { my_sigaction, sigaction } };

__attribute__((constructor)) static void init(void)
{
    extern char ***_NSGetArgv(void); extern int *_NSGetArgc(void);
    char **argv = *_NSGetArgv(); int argc = *_NSGetArgc();
    for (int i = 0; i < argc; i++) if (argv[i] && strcasestr(argv[i], "AION2.exe")) active = 1;
    const char *dir = getenv("SIGDIAG_DIR");
    if (active && dir)
    {
        char path[1024];
        snprintf(path, sizeof(path), "%s/sigdiag.%d.log", dir, getpid());
        logfd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    }
}
