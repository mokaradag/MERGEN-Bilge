using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// Tarayici baslamadan ozel job'a atanir; PID yeniden cozumlenmez.
public sealed class MergenBrowserJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct BasicLimits {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr Minimum, Maximum;
        public uint ActiveLimit;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters {
        public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits {
        public BasicLimits Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [StructLayout(LayoutKind.Sequential)] struct Accounting {
        public long UserTime, KernelTime, PeriodUserTime, PeriodKernelTime;
        public uint PageFaults, Total, Active, Terminated;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct Startup {
        public uint Size;
        public string Reserved, Desktop, Title;
        public uint X, Y, Width, Height, XChars, YChars, Fill, Flags;
        public ushort Show, ReservedSize;
        public IntPtr ReservedData, Input, Output, Error;
    }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo {
        public IntPtr Process, Thread;
        public uint Pid, Tid;
    }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits info, int size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool QueryInformationJobObject(IntPtr job, int kind, out Accounting info, int size, IntPtr length);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcess(string app, StringBuilder command, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref Startup startup, out ProcessInfo info);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool DuplicateHandle(IntPtr source, IntPtr handle, IntPtr target, out IntPtr copy, uint access, bool inherit, uint options);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

    IntPtr job, root;
    public bool Stopped { get; private set; }
    // Basarisiz adim adi; yalniz sabit ASCII asama adlari, arguman/yol yok.
    public static string LastStage = "";

    static void Check(bool ok) { if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    static IntPtr Inherited(int id) {
        IntPtr copy;
        Check(DuplicateHandle(GetCurrentProcess(), GetStdHandle(id), GetCurrentProcess(), out copy, 0, true, 2));
        return copy;
    }
    // CommandLineToArgvW/CRT kurali; Unicode cwd ve argv dogrudan CreateProcessW'ye gider.
    public static string Quote(string value) {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            result.Append(c);
            slashes = 0;
        }
        return result.Append('\\', slashes * 2).Append('"').ToString();
    }
    public MergenBrowserJob(string executable, string[] args, string cwd) {
        ProcessInfo pi = new ProcessInfo();
        IntPtr output = IntPtr.Zero, error = IntPtr.Zero;
        try {
            LastStage = "create_job";
            job = CreateJobObject(IntPtr.Zero, null);
            Check(job != IntPtr.Zero);
            LastStage = "job_limits";
            var limits = new ExtendedLimits();
            limits.Basic.Flags = 0x2000; // KILL_ON_JOB_CLOSE; breakaway izni verilmez.
            Check(SetInformationJobObject(job, 9, ref limits, Marshal.SizeOf(limits)));
            LastStage = "std_handles";
            output = Inherited(-11); error = Inherited(-12);
            var si = new Startup();
            si.Size = (uint)Marshal.SizeOf(si);
            si.Flags = 0x101; si.Show = 0;
            si.Output = output; si.Error = error;
            LastStage = "create_process";
            var command = new StringBuilder(Quote(executable));
            foreach (string arg in args) command.Append(' ').Append(Quote(arg));
            Check(CreateProcess(executable, command, IntPtr.Zero, IntPtr.Zero, true,
                0x08000004, IntPtr.Zero, cwd, ref si, out pi)); // NO_WINDOW | SUSPENDED
            root = pi.Process;
            LastStage = "assign";
            Check(AssignProcessToJobObject(job, root));
            LastStage = "resume";
            Check(ResumeThread(pi.Thread) != 0xffffffff);
            LastStage = "";
        } catch {
            // Atama basarisizsa henuz baslamamis kok kendi taniticisiyla kapanir.
            if (root != IntPtr.Zero) TerminateProcess(root, 1);
            Dispose();
            throw;
        } finally {
            if (pi.Thread != IntPtr.Zero) CloseHandle(pi.Thread);
            if (output != IntPtr.Zero) CloseHandle(output);
            if (error != IntPtr.Zero) CloseHandle(error);
        }
    }
    public int? ExitCode {
        get {
            uint wait = WaitForSingleObject(root, 0);
            if (wait == 258) return null;
            Check(wait == 0);
            uint code; Check(GetExitCodeProcess(root, out code));
            return unchecked((int)code);
        }
    }
    public uint Active {
        get {
            Accounting info;
            Check(QueryInformationJobObject(job, 1, out info, Marshal.SizeOf(typeof(Accounting)), IntPtr.Zero));
            return info.Active;
        }
    }
    // Yalniz bu job'un sonlandirdigi kok bu kodla cikar; dogal cikis kodu korunur.
    public const uint OwnedStopCode = 0x4D474E53;
    // Temizlik tanisi: yalniz sabit asama adi ve sayilar (kalan surec, gecen ms).
    public string CleanupStage { get; private set; }
    public uint CleanupActive { get; private set; }
    public long CleanupMilliseconds { get; private set; }
    public void Stop(int milliseconds) {
        var timer = System.Diagnostics.Stopwatch.StartNew();
        CleanupStage = "terminate";
        Check(TerminateJobObject(job, OwnedStopCode));
        CleanupStage = "cleanup_wait";
        while (true) {
            CleanupActive = Active;
            // Job sayaci kok taniticisi sinyallenmeden once sifirlanabilir; ikisi birlikte beklenir.
            uint rootWait = WaitForSingleObject(root, 0);
            Check(rootWait == 0 || rootWait == 258);
            CleanupMilliseconds = timer.ElapsedMilliseconds;
            if (CleanupActive == 0 && rootWait == 0) break;
            if (CleanupMilliseconds >= milliseconds) throw new TimeoutException();
            Thread.Sleep(10);
            // Sonlandirma sirasinda olusmakta olan torun job'a sonradan katilabilir; tekrar sonlandir.
            CleanupStage = "terminate";
            Check(TerminateJobObject(job, OwnedStopCode));
            CleanupStage = "cleanup_wait";
        }
        // Yaris yok: karar temizlik ve kok cikisi dogrulandiktan sonra gercek cikis kodundan verilir.
        CleanupStage = "exit_code";
        uint raw;
        Check(GetExitCodeProcess(root, out raw));
        Stopped = raw == OwnedStopCode;
        CleanupStage = "";
    }
    public void Dispose() {
        if (job != IntPtr.Zero) { CloseHandle(job); job = IntPtr.Zero; }
        if (root != IntPtr.Zero) { CloseHandle(root); root = IntPtr.Zero; }
    }
}
