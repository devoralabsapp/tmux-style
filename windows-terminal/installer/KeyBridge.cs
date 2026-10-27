using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using System.Web.Script.Serialization;

internal static class KeyBridge
{
    const int HookId=13, KeyDown=0x100, SysKeyDown=0x104;
    static IntPtr hook=IntPtr.Zero, armedWindow=IntPtr.Zero;
    static HookProc callback=OnKey;
    static bool armed, passThrough, shiftTabs;
    static int prefix=0x41, armedAt;
    static HashSet<int> consumed=new HashSet<int>();
    static NotifyIcon tray;
    static EventWaitHandle stopEvent;
    delegate IntPtr HookProc(int code,IntPtr message,IntPtr data);
    [StructLayout(LayoutKind.Sequential)] struct KeyData {public uint vk,scan,flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] struct Input {public uint type;public InputUnion union;}
    [StructLayout(LayoutKind.Explicit)] struct InputUnion {
        [FieldOffset(0)] public Keyboard keyboard;
        [FieldOffset(0)] public Mouse mouse;
    }
    [StructLayout(LayoutKind.Sequential)] struct Keyboard {public ushort vk,scan;public uint flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] struct Mouse {public int x,y;public uint data,flags,time;public UIntPtr extra;}
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id,HookProc proc,IntPtr module,uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr handle);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr handle,int code,IntPtr message,IntPtr data);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,Input[] inputs,int size);
    [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window,int command);
    [DllImport("kernel32.dll",CharSet=CharSet.Auto)] static extern IntPtr GetModuleHandle(string name);

    static bool Down(int key){return (GetAsyncKeyState(key)&0x8000)!=0;}
    static bool IsTerminal(IntPtr window){
        uint pid;GetWindowThreadProcessId(window,out pid);
        try{return Process.GetProcessById((int)pid).ProcessName.Equals("WindowsTerminal",StringComparison.OrdinalIgnoreCase);}catch{return false;}
    }
    internal static string Resolve(int vk,bool ctrl,bool shift,bool alt){
        if(alt)return null;
        if(ctrl){
            if(vk>=0x25&&vk<=0x28)return "alt+shift+"+Arrow(vk);
            if(vk==0x4f)return "ctrl+alt+o";
            if(vk==0x45)return "ctrl+alt+e";
            if(vk==0x53)return "ctrl+alt+s";
            return null;
        }
        if(vk>=0x31&&vk<=0x39&&!shift)return "ctrl+alt+"+(char)vk;
        if(vk>=0x25&&vk<=0x28&&!shift)return "alt+"+Arrow(vk);
        if(vk==0xdc&&shift)return "ctrl+alt+v";
        if(vk==0xbd&&!shift)return "ctrl+alt+h";
        if(vk==0x43&&!shift)return "ctrl+alt+c";
        if(vk==0x52)return shift?"ctrl+alt+shift+r":"ctrl+alt+r";
        if(vk==0x5a&&!shift)return "ctrl+shift+z";
        if(vk==0x58)return shift?"ctrl+alt+shift+x":"ctrl+shift+w";
        if(vk==0x51&&shift)return "ctrl+alt+shift+q";
        if(vk==9&&!shift)return "ctrl+alt+l";
        if(vk==0xdb&&!shift)return "ctrl+alt+[";
        if(vk==0xdd&&!shift)return "ctrl+alt+]";
        if(vk==0xbf&&shift)return "ctrl+shift+p";
        if(vk==0x44&&!shift)return "@minimize";
        return null;
    }
    static string Arrow(int vk){return vk==0x25?"left":vk==0x26?"up":vk==0x27?"right":"down";}
    static int Key(string key){
        switch(key){case "ctrl":return 0x11;case "alt":return 0x12;case "shift":return 0x10;
            case "left":return 0x25;case "up":return 0x26;case "right":return 0x27;case "down":return 0x28;
            case "[":return 0xdb;case "]":return 0xdd;case "tab":return 9;
            case "f11":return 0x7a;case "f12":return 0x7b;}
        return (int)Char.ToUpperInvariant(key[0]);
    }
    static void Emit(string chord,IntPtr target){
        if(GetForegroundWindow()!=target)return;
        if(chord=="@minimize"){ShowWindowAsync(target,6);return;}
        List<Input> inputs=new List<Input>();
        Action<int,bool> add=delegate(int vk,bool up){Input x=new Input();x.type=1;x.union.keyboard.vk=(ushort)vk;x.union.keyboard.flags=up?2u:0u;inputs.Add(x);};
        int[] modifiers={0x11,0x12,0x10};List<int> held=new List<int>();
        foreach(int modifier in modifiers)if(Down(modifier)){held.Add(modifier);add(modifier,true);}
        string[] parts=chord.Split('+');
        for(int i=0;i<parts.Length-1;i++)add(Key(parts[i]),false);
        add(Key(parts[parts.Length-1]),false);add(Key(parts[parts.Length-1]),true);
        for(int i=parts.Length-2;i>=0;i--)add(Key(parts[i]),true);
        foreach(int modifier in held)add(modifier,false);
        SendInput((uint)inputs.Count,inputs.ToArray(),Marshal.SizeOf(typeof(Input)));
    }
    static void Notice(string message){tray.Text=passThrough?"Tmux Style: OFF (F12 to enable)":"Tmux Style: Ctrl-"+(prefix==0x41?"A":"B");tray.ShowBalloonTip(1800,"Tmux Style keys",message,ToolTipIcon.Info);}
    static IntPtr OnKey(int code,IntPtr message,IntPtr pointer){
        if(code<0)return CallNextHookEx(hook,code,message,pointer);
        KeyData data=(KeyData)Marshal.PtrToStructure(pointer,typeof(KeyData));
        if((data.flags&0x10)!=0)return CallNextHookEx(hook,code,message,pointer); // ignore our injected shortcuts
        int vk=(int)data.vk;bool down=message.ToInt32()==KeyDown||message.ToInt32()==SysKeyDown;
        if(!down&&consumed.Remove(vk))return new IntPtr(1);
        IntPtr window=GetForegroundWindow();
        if(!IsTerminal(window)){armed=false;return CallNextHookEx(hook,code,message,pointer);}
        if(!down||vk==0x10||vk==0x11||vk==0x12||vk>=0xa0&&vk<=0xa5)return CallNextHookEx(hook,code,message,pointer);
        if(consumed.Contains(vk))return new IntPtr(1);
        bool ctrl=Down(0x11),shift=Down(0x10),alt=Down(0x12);
        bool handled=false;string emit=null;
        if(vk==0x7b&&!ctrl&&!alt&&!shift){passThrough=!passThrough;armed=false;handled=true;Notice(passThrough?"OFF: keys now pass to the terminal. F12 restores mappings.":"ON: Ctrl-a mappings restored.");}
        else if(!passThrough){
            if(armed&&(Environment.TickCount-armedAt>5000||window!=armedWindow))armed=false;
            if(armed){
                armed=false;handled=true;
                if(vk==prefix&&ctrl&&!alt&&!shift)emit=prefix==0x41?"ctrl+a":"ctrl+b";
                else if(vk!=27){emit=Resolve(vk,ctrl,shift,alt);if(emit==null)Notice("No Windows equivalent for this tmux action. Ctrl-a ? shows available actions.");}
            }else if(vk==prefix&&ctrl&&!alt&&!shift){armed=true;armedWindow=window;armedAt=Environment.TickCount;handled=true;}
            else if(shift&&!alt&&vk==0x26&&!ctrl){prefix=0x42;shiftTabs=false;handled=true;emit="alt+f12";Notice("Outer mode: Ctrl-b. Shift+Down restores Ctrl-a and Shift tab controls.");}
            else if(shift&&!alt&&vk==0x28&&!ctrl){prefix=0x41;shiftTabs=true;handled=true;emit="alt+f11";Notice("Inner mode: Ctrl-a; Shift+Left/Right switches tabs.");}
            else if(shiftTabs&&!alt&&shift&&(vk==0x25||vk==0x27)){handled=true;emit=ctrl?"ctrl+alt+shift+"+Arrow(vk):"ctrl+alt+"+Arrow(vk);}
            else if(shiftTabs&&ctrl&&!alt&&!shift&&vk==0x54){handled=true;emit="ctrl+alt+c";}
        }
        if(!handled)return CallNextHookEx(hook,code,message,pointer);
        consumed.Add(vk);if(emit!=null)Emit(emit,window);return new IntPtr(1);
    }
    static int SelfTest(string report){
        var checks=new Dictionary<string,string>();
        checks["prefix c"]=Resolve(0x43,false,false,false);
        checks["prefix pipe"]=Resolve(0xdc,false,true,false);
        checks["prefix minus"]=Resolve(0xbd,false,false,false);
        checks["prefix r"]=Resolve(0x52,false,false,false);
        checks["prefix R"]=Resolve(0x52,false,true,false);
        checks["prefix Ctrl-o"]=Resolve(0x4f,true,false,false);
        checks["prefix Ctrl-Up"]=Resolve(0x26,true,false,false);
        checks["prefix z"]=Resolve(0x5a,false,false,false);
        checks["prefix x"]=Resolve(0x58,false,false,false);
        checks["prefix X"]=Resolve(0x58,false,true,false);
        if(checks["prefix c"]!="ctrl+alt+c"||checks["prefix pipe"]!="ctrl+alt+v"||checks["prefix minus"]!="ctrl+alt+h"||checks["prefix r"]==checks["prefix R"]||checks["prefix Ctrl-Up"]!="alt+shift+up"||Resolve(0x43,false,false,true)!=null)return 1;
        File.WriteAllText(report,new JavaScriptSerializer().Serialize(new {passed=true,mappings=checks,scope="Windows Terminal foreground only; no keys recorded"}));return 0;
    }
    [STAThread] static int Main(string[] args){
        if(args.Length==2&&args[0]=="--self-test")return SelfTest(args[1]);
        string suffix=System.Security.Principal.WindowsIdentity.GetCurrent().User.Value;
        string stopName="Local\\TmuxStyle.Keys.Stop."+suffix;
        if(args.Length==1&&args[0]=="--stop"){try{EventWaitHandle.OpenExisting(stopName).Set();}catch{}return 0;}
        bool created;using(Mutex mutex=new Mutex(true,"Local\\TmuxStyle.Keys."+suffix,out created)){
            if(!created)return 0;
            Application.EnableVisualStyles();
            using(stopEvent=new EventWaitHandle(false,EventResetMode.AutoReset,stopName))
            using(tray=new NotifyIcon()){
                tray.Icon=System.Drawing.SystemIcons.Application;tray.Text="Tmux Style: Ctrl-A";tray.Visible=true;
                ContextMenuStrip menu=new ContextMenuStrip();menu.Items.Add("F12: toggle pass-through",null,delegate{passThrough=!passThrough;Notice(passThrough?"Mappings OFF":"Mappings ON");});menu.Items.Add("Exit key bridge",null,delegate{Application.Exit();});tray.ContextMenuStrip=menu;
                hook=SetWindowsHookEx(HookId,callback,GetModuleHandle(null),0);
                if(hook==IntPtr.Zero)return 2;
                int absent=0;using(System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer()){
                    timer.Interval=1000;timer.Tick+=delegate{
                        if(stopEvent.WaitOne(0)){Application.Exit();return;}
                        absent=Process.GetProcessesByName("WindowsTerminal").Length==0?absent+1:0;
                        if(absent>20)Application.Exit();
                    };timer.Start();Application.Run();
                }
                UnhookWindowsHookEx(hook);tray.Visible=false;
            }
        }return 0;
    }
}
