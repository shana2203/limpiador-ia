using System;
using System.Drawing;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static int Main()
    {
        try
        {
            using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("Limpiador.ps1"))
            using (var reader = new StreamReader(resource))
            using (var runspace = RunspaceFactory.CreateRunspace())
            using (var shell = PowerShell.Create())
            using (var icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath))
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                runspace.SessionStateProxy.SetVariable("launcherIcon", icon);
                shell.Runspace = runspace;
                shell.AddScript(reader.ReadToEnd());
                shell.Invoke();

                if (shell.HadErrors)
                    throw new InvalidOperationException(shell.Streams.Error[0].ToString());
            }

            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Limpiador de IA", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}

public static class WindowAppearance
{
    private const int ImmersiveDarkMode = 20;

    public static IMessageFilter GuardWorkInput(IntPtr window)
    {
        var guard = new WorkInputGuard(window);
        Application.AddMessageFilter(guard);
        return guard;
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);

    public static void SetDarkTitleBar(IntPtr window, bool dark)
    {
        int enabled = dark ? 1 : 0;
        DwmSetWindowAttribute(window, ImmersiveDarkMode, ref enabled, sizeof(int));
    }
}

public static class DriveRecycleBin
{

    [StructLayout(LayoutKind.Sequential)]
    public struct Usage
    {
        public uint StructSize;
        public long Bytes;
        public long Items;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHQueryRecycleBin(string root, ref Usage usage);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHEmptyRecycleBin(IntPtr parent, string root, uint flags);

    public static Usage Query(string root)
    {
        var usage = new Usage { StructSize = (uint)Marshal.SizeOf(typeof(Usage)) };
        Marshal.ThrowExceptionForHR(SHQueryRecycleBin(root, ref usage));
        return usage;
    }

    public static void Empty(IntPtr parent, string root)
    {
        int result = SHEmptyRecycleBin(parent, root, 1);
        const int Cancelled = unchecked((int)0x800704C7);
        if (result != Cancelled)
            Marshal.ThrowExceptionForHR(result);
    }

    // IFileOperation preserves the Shell's Recycle Bin behavior for large files.
    [ComImport]
    [Guid("947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOperation
    {
        void Advise(IntPtr sink, out uint cookie);
        void Unadvise(uint cookie);
        void SetOperationFlags(uint flags);
        void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string message);
        void SetProgressDialog(IntPtr dialog);
        void SetProperties(IntPtr properties);
        void SetOwnerWindow(IntPtr parent);
        void ApplyPropertiesToItem(IntPtr item);
        void ApplyPropertiesToItems(IntPtr items);
        void RenameItem(IntPtr item, [MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr sink);
        void RenameItems(IntPtr items, [MarshalAs(UnmanagedType.LPWStr)] string name);
        void MoveItem(IntPtr item, IntPtr destination, [MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr sink);
        void MoveItems(IntPtr items, IntPtr destination);
        void CopyItem(IntPtr item, IntPtr destination, [MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr sink);
        void CopyItems(IntPtr items, IntPtr destination);
        void DeleteItem(IntPtr item, IntPtr sink);
        void DeleteItems(IntPtr items);
        void NewItem(IntPtr destination, uint attributes, [MarshalAs(UnmanagedType.LPWStr)] string name,
            [MarshalAs(UnmanagedType.LPWStr)] string template, IntPtr sink);
        void PerformOperations();
        void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool aborted);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int SHCreateItemFromParsingName(string path, IntPtr context, ref Guid interfaceId,
        out IntPtr item);

    public static void Recycle(IntPtr parent, string path)
    {
        var shellItemId = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");
        IntPtr item;
        Marshal.ThrowExceptionForHR(SHCreateItemFromParsingName(path, IntPtr.Zero, ref shellItemId, out item));
        try
        {
            var classId = new Guid("3AD05575-8857-4850-9277-11B85BDB8E09");
            var operation = (IFileOperation)Activator.CreateInstance(Type.GetTypeFromCLSID(classId));
            try
            {
                const uint silent = 0x0004;
                const uint noConfirmation = 0x0010;
                const uint noConnectedElements = 0x2000;
                const uint warnBeforePermanentDelete = 0x4000;
                const uint recycleOnDelete = 0x00080000;
                operation.SetOwnerWindow(parent);
                operation.SetOperationFlags(silent | noConfirmation | noConnectedElements |
                    warnBeforePermanentDelete | recycleOnDelete);
                operation.DeleteItem(item, IntPtr.Zero);
                operation.PerformOperations();
                bool aborted;
                operation.GetAnyOperationsAborted(out aborted);
                if (aborted || File.Exists(path))
                    throw new IOException("Windows no pudo enviar el archivo a la Papelera.");
            }
            finally { Marshal.ReleaseComObject(operation); }
        }
        finally { Marshal.Release(item); }
    }
}

public static class DriveUsage
{
    public class Entry
    {
        public string Path { get; set; }
        public long Bytes { get; set; }
        public bool Directory { get; set; }
    }

    public class Result
    {
        public long Used { get; set; }
        public int Skipped { get; set; }
        public System.Collections.Generic.List<Entry> Entries { get; private set; }

        public Result()
        {
            Entries = new System.Collections.Generic.List<Entry>();
        }
    }

    public static System.Threading.Tasks.Task<Result> ScanAsync(string root)
    {
        return System.Threading.Tasks.Task.Run(() => Scan(root));
    }

    private static Result Scan(string root)
    {
        var info = new DriveInfo(root);
        var result = new Result { Used = info.TotalSize - info.TotalFreeSpace };
        foreach (FileSystemInfo item in info.RootDirectory.EnumerateFileSystemInfos())
        {
            if ((item.Attributes & FileAttributes.ReparsePoint) != 0)
            {
                result.Skipped++;
                continue;
            }

            var dir = item as DirectoryInfo;
            long bytes = dir == null ? ((FileInfo)item).Length : MeasureDirectory(dir, result);
            result.Entries.Add(new Entry { Path = item.FullName, Bytes = bytes, Directory = dir != null });
        }
        result.Entries.Sort((left, right) => right.Bytes.CompareTo(left.Bytes));
        return result;
    }

    private static long MeasureDirectory(DirectoryInfo directory, Result result)
    {
        var folders = new System.Collections.Generic.Stack<DirectoryInfo>();
        folders.Push(directory);
        long bytes = 0;
        while (folders.Count > 0)
        {
            try
            {
                foreach (FileSystemInfo child in folders.Pop().EnumerateFileSystemInfos())
                {
                    if ((child.Attributes & FileAttributes.ReparsePoint) != 0)
                    {
                        result.Skipped++;
                        continue;
                    }
                    var subfolder = child as DirectoryInfo;
                    if (subfolder != null)
                        folders.Push(subfolder);
                    else
                        bytes += ((FileInfo)child).Length;
                }
            }
            catch (UnauthorizedAccessException) { result.Skipped++; }
            catch (IOException) { result.Skipped++; }
        }
        return bytes;
    }
}

internal sealed class WorkInputGuard : IMessageFilter
{
    private readonly IntPtr window;

    internal WorkInputGuard(IntPtr window)
    {
        this.window = window;
    }

    [DllImport("user32.dll")]
    private static extern bool IsChild(IntPtr parent, IntPtr child);

    public bool PreFilterMessage(ref Message message)
    {
        int id = message.Msg;
        bool input = (id >= 0x100 && id <= 0x109) ||
                     (id >= 0x200 && id <= 0x20E) || id == 0x7B;
        return input && (message.HWnd == window || IsChild(window, message.HWnd));
    }
}

public sealed class CleanupProgressBar : Control
{
    private readonly System.Windows.Forms.Timer animation;
    private int position;
    private int total;

    public int Value { get; private set; }

    public CleanupProgressBar()
    {
        DoubleBuffered = true;
        animation = new System.Windows.Forms.Timer();
        animation.Interval = 33;
        animation.Tick += (sender, args) =>
        {
            position = (position + 7) % Math.Max(1, Width + Width / 4);
            Invalidate();
        };
    }

    public void Begin(int maximum)
    {
        total = maximum;
        Value = position = 0;
        if (total == 0)
            animation.Start();
        Invalidate();
    }

    public void Advance(int processed)
    {
        Value = processed;
        Invalidate();
    }

    public void End()
    {
        animation.Stop();
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        int width = total == 0 ? Width / 4 : (int)((long)Width * Value / total);
        int left = total == 0 ? position - width : 0;
        using (var fill = new SolidBrush(ForeColor))
            args.Graphics.FillRectangle(fill, left, 0, width, Height);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            animation.Dispose();
        base.Dispose(disposing);
    }
}
