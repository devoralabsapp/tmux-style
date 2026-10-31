using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

internal static class SetupProgram
{
    internal static readonly string Version=Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
    internal static string Quote(string text){return "'"+text.Replace("'","''")+"'";}
    internal static string Extract(string destination){
        Directory.CreateDirectory(destination);
        using(Stream resource=Assembly.GetExecutingAssembly().GetManifestResourceStream("TmuxStyle.Payload.zip"))
        using(ZipArchive zip=new ZipArchive(resource,ZipArchiveMode.Read)){
            foreach(ZipArchiveEntry entry in zip.Entries){
                string path=Path.GetFullPath(Path.Combine(destination,entry.FullName));
                if(!path.StartsWith(Path.GetFullPath(destination)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Invalid package path");
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                using(Stream input=entry.Open())using(Stream output=File.Create(path))input.CopyTo(output);
            }
        }return destination;
    }
    internal static int RunPowerShell(string command,Action<string> output){
        ProcessStartInfo info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe"));
        info.Arguments="-NoLogo -NoProfile -NonInteractive -EncodedCommand "+Convert.ToBase64String(Encoding.Unicode.GetBytes("$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; try { "+command+"; exit 0 } catch { Write-Output $_.Exception.Message; exit 1 }"));
        info.UseShellExecute=false;info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
        // A caller such as PowerShell 7 may carry incompatible module paths.
        // Let the child Windows PowerShell initialize its own module path.
        info.EnvironmentVariables.Remove("PSModulePath");
        using(Process process=new Process()){
            process.StartInfo=info;
            process.OutputDataReceived+=delegate(object sender,DataReceivedEventArgs e){if(e.Data!=null)output(e.Data);};
            process.ErrorDataReceived+=delegate(object sender,DataReceivedEventArgs e){if(e.Data!=null)output(e.Data);};
            process.Start();process.BeginOutputReadLine();process.BeginErrorReadLine();process.WaitForExit();return process.ExitCode;
        }
    }
    [STAThread] static int Main(string[] args){
        if(args.Length==3&&args[0]=="--self-test"&&args[1]=="--report"){
            try{
                string directory=Extract(Path.Combine(Path.GetTempPath(),"TmuxStyleSelfTest-"+Guid.NewGuid().ToString("N")));
                string report=Path.GetFullPath(args[2]);Directory.CreateDirectory(Path.GetDirectoryName(report));
                string command=". ([scriptblock]::Create([IO.File]::ReadAllText("+Quote(Path.Combine(directory,"test-release.ps1"))+"))) -SourceDirectory "+Quote(directory)+" -ReportFile "+Quote(report);
                StringBuilder log=new StringBuilder();int result=RunPowerShell(command,delegate(string line){lock(log){log.AppendLine(line);}});
                File.WriteAllText(report+".log",log.ToString());return result;
            }catch(Exception ex){File.WriteAllText(args[2]+".error",ex.ToString());return 1;}
        }
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new SetupForm());return 0;
    }
}

internal sealed class SetupForm:Form
{
    ComboBox theme,backend;TextBox directory,log;CheckBox shortcut,launch,terminal;Button install,restore;Label status;
    bool busy;
    public SetupForm(){
        Text="TMX / Windows Setup "+SetupProgram.Version;ClientSize=new Size(760,670);
        Icon=System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        MinimumSize=new Size(776,709);MaximumSize=new Size(1000,900);StartPosition=FormStartPosition.CenterScreen;
        BackColor=Color.FromArgb(16,22,25);ForeColor=Color.FromArgb(225,238,230);Font=new Font("Segoe UI",10);
        AutoScaleMode=AutoScaleMode.Dpi;
        Label title=new Label{Text="TMX",Font=new Font("Segoe UI Semibold",26),ForeColor=Color.FromArgb(159,228,190),Location=new Point(30,22),AutoSize=true};Controls.Add(title);
        Controls.Add(new Label{Text="PowerShell workspaces. Your tmux muscle memory.",Location=new Point(33,78),Size=new Size(690,28),ForeColor=Color.FromArgb(167,189,177)});
        Controls.Add(new Label{Text="Terminal",Location=new Point(34,121),AutoSize=true});
        backend=new ComboBox{Location=new Point(205,117),Size=new Size(452,30),DropDownStyle=ComboBoxStyle.DropDownList};
        backend.Items.AddRange(new object[]{"WezTerm - real bottom bar: CPU, RAM, tabs, clock","Windows Terminal - colors and panes (no bottom bar)"});backend.SelectedIndex=0;Controls.Add(backend);
        Controls.Add(new Label{Text="Default theme",Location=new Point(34,127),AutoSize=true});
        theme=new ComboBox{Location=new Point(205,123),Size=new Size(260,30),DropDownStyle=ComboBoxStyle.DropDownList};
        theme.Items.AddRange(new object[]{"Aurora","Midnight","Ember","Paper","Neon","Command Line (Black)","Code Spectrum","Hacker Matrix"});theme.SelectedIndex=0;Controls.Add(theme);
        Controls.Add(new Label{Text="Starting folder",Location=new Point(34,174),AutoSize=true});
        directory=new TextBox{Location=new Point(205,169),Size=new Size(452,30),Text=Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)};Controls.Add(directory);
        Button browse=new Button{Text="...",Location=new Point(668,168),Size=new Size(54,30)};browse.Click+=delegate{using(FolderBrowserDialog dialog=new FolderBrowserDialog()){dialog.SelectedPath=directory.Text;if(dialog.ShowDialog()==DialogResult.OK)directory.Text=dialog.SelectedPath;}};Controls.Add(browse);
        shortcut=new CheckBox{Text="Create a 3-pane workspace shortcut on Desktop",Checked=true,Location=new Point(34,218),AutoSize=true};Controls.Add(shortcut);
        launch=new CheckBox{Text="Open the workspace after installing",Checked=true,Location=new Point(34,251),AutoSize=true};Controls.Add(launch);
        terminal=new CheckBox{Text="Install Microsoft Windows Terminal if missing (requires internet)",Checked=true,Location=new Point(34,284),AutoSize=true};Controls.Add(terminal);
        Controls.Add(new Label{Text="Ctrl-a, then | / - / c / r / z / x. F12 passes keys through.\nThe key bridge only handles Windows Terminal while it is in front. It does not record keys.",Location=new Point(34,328),Size=new Size(690,50),ForeColor=Color.FromArgb(197,181,237)});
        log=new TextBox{Location=new Point(34,390),Size=new Size(688,125),Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Vertical,BackColor=Color.FromArgb(24,39,34),ForeColor=Color.FromArgb(225,238,230),BorderStyle=BorderStyle.FixedSingle};Controls.Add(log);
        status=new Label{Text="Per-user installation. Existing settings are backed up. No administrator required.",Location=new Point(34,532),Size=new Size(688,25),ForeColor=Color.FromArgb(167,189,177)};Controls.Add(status);
        restore=new Button{Text="Restore previous settings",Location=new Point(34,568),Size=new Size(220,35)};restore.Click+=async delegate{await Restore();};Controls.Add(restore);
        install=new Button{Text="Install workspace",Location=new Point(502,563),Size=new Size(220,42),BackColor=Color.FromArgb(159,228,190),ForeColor=Color.FromArgb(18,32,27),FlatStyle=FlatStyle.Flat};install.Click+=async delegate{await Install();};Controls.Add(install);
        // Make room for the engine selector without overlapping the existing form.
        foreach(Control control in Controls){if(control!=title && control!=backend && control.Top>=123)control.Top+=50;}
        terminal.Text="Download the selected official terminal if missing (requires internet)";
        foreach(Control control in Controls){Label help=control as Label;if(help!=null && help.Text.StartsWith("Ctrl-a,"))help.Text="Ctrl-a, then | / - / c / r / z / x. F12 passes keys through.\nWezTerm: native shortcuts + bottom bar. Windows Terminal: foreground key bridge.";}
        FormClosing+=delegate(object sender,FormClosingEventArgs e){if(busy){e.Cancel=true;MessageBox.Show(this,"Please wait for installation to finish.","Tmux Style");}};
    }
    void Write(string line){if(IsDisposed)return;if(InvokeRequired){BeginInvoke(new Action<string>(Write),line);return;}log.AppendText(line+Environment.NewLine);}
    void SetBusy(bool value){busy=value;install.Enabled=!value;restore.Enabled=!value;theme.Enabled=!value;backend.Enabled=!value;directory.Enabled=!value;}
    async Task Install(){
        if(!Directory.Exists(directory.Text)){MessageBox.Show(this,"Choose an existing starting folder.","Tmux Style");return;}
        string selected=new string[]{"aurora","midnight","ember","paper","neon","black","code","hacker"}[theme.SelectedIndex],folder=directory.Text;
        string engine=backend.SelectedIndex==0?"wezterm":"windows-terminal";
        bool createShortcut=shortcut.Checked,open=launch.Checked,download=terminal.Checked;
        SetBusy(true);status.Text="Installing...";log.Clear();
        try{
            int result=await Task.Run(delegate{
                string package=SetupProgram.Extract(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"TmuxStyleWindows","packages",SetupProgram.Version+"-"+Guid.NewGuid().ToString("N").Substring(0,6)));
                string command=". ([scriptblock]::Create([IO.File]::ReadAllText("+SetupProgram.Quote(Path.Combine(package,"install-runner.ps1"))+"))) -SourceDirectory "+SetupProgram.Quote(package)+" -Theme "+SetupProgram.Quote(selected)+" -StartingDirectory "+SetupProgram.Quote(folder);
                command+=" -Backend "+SetupProgram.Quote(engine);
                if(!createShortcut)command+=" -NoShortcut";if(open)command+=" -Launch";if(download)command+=" -InstallTerminal";
                return SetupProgram.RunPowerShell(command,Write);
            });
            status.Text=result==0?(engine=="wezterm"?"Installed. Open PowerShell or CMD and run tmx. Ctrl-a d detaches.":"Installed. Ctrl-a is ready in new Tmux Style PowerShell tabs."):"Installation failed. See the log above; existing sessions remain open.";
        }catch(Exception ex){Write(ex.Message);status.Text="Installation failed.";}finally{SetBusy(false);}
    }
    async Task Restore(){
        string path=backend.SelectedIndex==0?Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"TmuxStyleWindows","wezterm","restore-wezterm.ps1"):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"TmuxStyleWindows","restore.ps1");
        if(!File.Exists(path)){MessageBox.Show(this,"There is no previous Tmux Style installation to restore.","Tmux Style");return;}
        if(MessageBox.Show(this,"Restore the settings saved before the last installation?\nClose workspace windows first.","Tmux Style",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
        SetBusy(true);try{
            int result=await Task.Run(delegate{return SetupProgram.RunPowerShell(". ([scriptblock]::Create([IO.File]::ReadAllText("+SetupProgram.Quote(path)+")))",Write);});
            status.Text=result==0?"Previous settings restored.":"Restore stopped. See the log to preserve your newer settings.";
        }finally{SetBusy(false);}
    }
}
