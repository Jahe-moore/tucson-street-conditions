param([long]$Hwnd, [string]$ClickText = '', [switch]$Dump)
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class IE {
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern uint RegisterWindowMessage(string s);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out UIntPtr r);
  [DllImport("oleacc.dll", PreserveSig=false)] [return: MarshalAs(UnmanagedType.Interface)]
  public static extern object ObjectFromLresult(UIntPtr l, [MarshalAs(UnmanagedType.LPStruct)] Guid iid, IntPtr w);
  public static object Doc(IntPtr h) {
    uint msg = RegisterWindowMessage("WM_HTML_GETOBJECT"); UIntPtr r;
    SendMessageTimeout(h, msg, IntPtr.Zero, IntPtr.Zero, 2, 2000, out r);
    return ObjectFromLresult(r, new Guid("626FC520-A41E-11CF-A731-00A0C9082637"), IntPtr.Zero);
  }
}
"@

