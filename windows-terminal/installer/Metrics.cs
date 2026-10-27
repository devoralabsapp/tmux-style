using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

// Local host counters only. No keyboard hook, network access or startup entry.
internal static class MetricsProgram {
    [StructLayout(LayoutKind.Sequential)] struct FileTime { public uint Low, High; public ulong Value { get { return ((ulong)High<<32)|Low; } } }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)] class MemoryStatus {
        public uint Length=(uint)Marshal.SizeOf(typeof(MemoryStatus)), Load;
        public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile, TotalVirtual, AvailableVirtual, AvailableExtended;
    }
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetSystemTimes(out FileTime idle,out FileTime kernel,out FileTime user);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GlobalMemoryStatusEx([In,Out] MemoryStatus status);
    static ulong previousIdle,previousTotal;
    static void Write(string path) {
        FileTime idle,kernel,user;
        if(!GetSystemTimes(out idle,out kernel,out user))throw new InvalidOperationException("GetSystemTimes failed");
        ulong total=kernel.Value+user.Value, delta=total-previousTotal;
        double cpu=previousTotal==0||delta==0?0:100.0*(1.0-(double)(idle.Value-previousIdle)/delta);
        previousIdle=idle.Value;previousTotal=total;
        MemoryStatus mem=new MemoryStatus();
        if(!GlobalMemoryStatusEx(mem))throw new InvalidOperationException("GlobalMemoryStatusEx failed");
        string json=String.Format(CultureInfo.InvariantCulture,
            "{{\"timestamp\":{0},\"cpu\":{1:0.0},\"ram\":{2},\"usedGiB\":{3:0.0},\"totalGiB\":{4:0.0}}}",
            (long)(DateTime.UtcNow-new DateTime(1970,1,1)).TotalSeconds,Math.Max(0,Math.Min(100,cpu)),mem.Load,
            (mem.TotalPhysical-mem.AvailablePhysical)/1073741824.0,mem.TotalPhysical/1073741824.0);
        string temp=path+"."+Process.GetCurrentProcess().Id+".tmp";
        File.WriteAllText(temp,json,new UTF8Encoding(false));
        // Readers either see the complete previous sample or the complete new one.
        if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);
    }
    static string Key(string path) {
        using(SHA256 sha=SHA256.Create())return "Local\\TmuxStyleMetrics-"+BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(Path.GetFullPath(path).ToLowerInvariant()))).Replace("-","").Substring(0,24);
    }
    [STAThread] static int Main(string[] args) {
        if(args.Length!=2)return 2;
        string mode=args[0],path=Path.GetFullPath(args[1]);
        try {
            if(mode=="--once") { Directory.CreateDirectory(Path.GetDirectoryName(path));Write(path);Thread.Sleep(250);Write(path);return 0; }
            if(mode=="--stop") { try { using(EventWaitHandle stop=EventWaitHandle.OpenExisting(Key(path)+"-stop"))stop.Set(); }catch(WaitHandleCannotBeOpenedException){}return 0; }
            if(mode!="--watch")return 2;
            bool owner;
            using(Mutex mutex=new Mutex(true,Key(path),out owner)) {
                if(!owner)return 0;
                using(EventWaitHandle stop=new EventWaitHandle(false,EventResetMode.ManualReset,Key(path)+"-stop")) {
                    Directory.CreateDirectory(Path.GetDirectoryName(path));int missing=0;
                    do {
                        try { Write(path); }catch(IOException){} // A reader can briefly hold a Windows file handle.
                        if(Process.GetProcessesByName("wezterm-gui").Length==0)missing++;else missing=0;
                    }while(missing<10&&!stop.WaitOne(2000));
                }
                mutex.ReleaseMutex();
            }
            return 0;
        }catch { return 1; }
    }
}
