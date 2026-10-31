using System;
using System.Diagnostics;
using System.IO;
using System.Text;

// Console entry point for PowerShell and CMD. Keep argv and Unicode paths intact
// without changing shell profiles or the user's PowerShell execution policy.
internal static class TmxCommand {
    private static string Quote(string value) { return "'"+value.Replace("'","''")+"'"; }
    public static int Main(string[] args) {
        try {
            string directory=Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName);
            string root=File.ReadAllText(Path.Combine(directory,"tmx-location.txt"),Encoding.UTF8).Trim();
            string[] quoted=Array.ConvertAll(args,Quote);
            string command="$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; try { & ([scriptblock]::Create([IO.File]::ReadAllText("+
                Quote(Path.Combine(root,"tmx.ps1"))+"))) -AssetDirectory "+Quote(root)+" -Arguments @("+
                String.Join(",",quoted)+"); exit 0 } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }";
            ProcessStartInfo info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe"));
            info.Arguments="-NoLogo -NoProfile -OutputFormat Text -EncodedCommand "+Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
            info.UseShellExecute=false;
            info.EnvironmentVariables.Remove("PSModulePath");
            using(Process child=Process.Start(info)){child.WaitForExit();return child.ExitCode;}
        } catch(Exception error) { Console.Error.WriteLine(error.Message);return 1; }
    }
}
