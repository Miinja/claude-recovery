// Acces bas niveau aux disques : liste des cles USB, verrouillage des volumes,
// ecriture brute. Aucune dependance hors du .NET Framework livre avec Windows.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace ClaudeRecovery
{
    public sealed class UsbDisk
    {
        public int Number;
        public string Model;
        public long Size;

        public override string ToString()
        {
            return string.Format("{0}  -  {1}  (disque {2})", Model, FormatSize(Size), Number);
        }

        public static string FormatSize(long bytes)
        {
            double gb = bytes / 1000000000.0;
            return gb >= 1 ? gb.ToString("0.#") + " Go" : (bytes / 1000000.0).ToString("0") + " Mo";
        }
    }

    public static class Disks
    {
        const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
        const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, OPEN_EXISTING = 3;
        const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x2D1400;
        const uint IOCTL_DISK_GET_LENGTH_INFO = 0x7405C;
        const uint IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS = 0x560000;
        const uint IOCTL_DISK_DELETE_DRIVE_LAYOUT = 0x7C100;
        const uint IOCTL_DISK_UPDATE_PROPERTIES = 0x70140;
        const uint FSCTL_LOCK_VOLUME = 0x90018, FSCTL_DISMOUNT_VOLUME = 0x90020;
        const int BusTypeUsb = 7;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa,
            uint creation, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inBuf, int inSize,
            byte[] outBuf, int outSize, out int returned, IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr FindFirstVolume(StringBuilder name, int size);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool FindNextVolume(IntPtr h, StringBuilder name, int size);

        [DllImport("kernel32.dll")]
        static extern bool FindVolumeClose(IntPtr h);

        static SafeFileHandle Open(string path, uint access)
        {
            return CreateFile(path, access, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero,
                OPEN_EXISTING, 0, IntPtr.Zero);
        }

        static string PhysicalPath(int number)
        {
            return @"\\.\PhysicalDrive" + number;
        }

        static string AsciiAt(byte[] buf, int offset)
        {
            if (offset <= 0 || offset >= buf.Length) return "";
            int end = offset;
            while (end < buf.Length && buf[end] != 0) end++;
            return Encoding.ASCII.GetString(buf, offset, end - offset).Trim();
        }

        /// <summary>Numeros des disques qui portent le volume donne (ex. \\.\C:).</summary>
        static List<int> DisksOfVolume(string volumePath)
        {
            var result = new List<int>();
            using (SafeFileHandle h = Open(volumePath, 0))
            {
                if (h.IsInvalid) return result;
                var buf = new byte[1024];
                int ret;
                if (!DeviceIoControl(h, IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, null, 0, buf, buf.Length, out ret, IntPtr.Zero))
                    return result;
                int count = BitConverter.ToInt32(buf, 0);
                for (int i = 0; i < count && 8 + i * 24 + 4 <= ret; i++)
                    result.Add(BitConverter.ToInt32(buf, 8 + i * 24));
            }
            return result;
        }

        /// <summary>Disques USB, hors disque(s) du systeme. Lecture seule.</summary>
        public static List<UsbDisk> ListUsb()
        {
            string sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
            List<int> systemDisks = DisksOfVolume(@"\\.\" + sys.Substring(0, 2));
            var disks = new List<UsbDisk>();
            for (int n = 0; n < 64; n++)
            {
                if (systemDisks.Contains(n)) continue;
                using (SafeFileHandle h = Open(PhysicalPath(n), GENERIC_READ))
                {
                    if (h.IsInvalid) continue;
                    var query = new byte[12];          // StorageDeviceProperty, PropertyStandardQuery
                    var buf = new byte[1024];
                    int ret;
                    if (!DeviceIoControl(h, IOCTL_STORAGE_QUERY_PROPERTY, query, query.Length, buf, buf.Length, out ret, IntPtr.Zero))
                        continue;
                    if (BitConverter.ToInt32(buf, 28) != BusTypeUsb) continue;
                    var len = new byte[8];
                    if (!DeviceIoControl(h, IOCTL_DISK_GET_LENGTH_INFO, null, 0, len, 8, out ret, IntPtr.Zero))
                        continue;                      // lecteur de cartes vide, par exemple
                    long size = BitConverter.ToInt64(len, 0);
                    if (size <= 0) continue;
                    string model = (AsciiAt(buf, BitConverter.ToInt32(buf, 12)) + " "
                                  + AsciiAt(buf, BitConverter.ToInt32(buf, 16))).Trim();
                    disks.Add(new UsbDisk { Number = n, Model = model.Length > 0 ? model : "Disque USB", Size = size });
                }
            }
            return disks;
        }

        /// <summary>
        /// Ouvre le disque en ecriture brute : verrouille et demonte ses volumes, efface sa
        /// table de partitions. Les verrous sont tenus jusqu'a Dispose().
        /// </summary>
        public static RawDisk OpenForWrite(UsbDisk disk)
        {
            // Garde-fou : on revérifie juste avant d'ecrire que c'est toujours la meme cle.
            UsbDisk now = ListUsb().Find(delegate(UsbDisk d) { return d.Number == disk.Number; });
            if (now == null || now.Size != disk.Size || now.Model != disk.Model)
                throw new IOException("La clé a changé depuis sa sélection. Actualisez la liste et recommencez.");

            var locks = new List<SafeFileHandle>();
            try
            {
                var name = new StringBuilder(260);
                IntPtr find = FindFirstVolume(name, name.Capacity);
                if (find != new IntPtr(-1))
                {
                    try
                    {
                        do
                        {
                            string vol = name.ToString().TrimEnd('\\');
                            if (!DisksOfVolume(vol).Contains(disk.Number)) continue;
                            SafeFileHandle v = Open(vol, GENERIC_READ | GENERIC_WRITE);
                            if (v.IsInvalid) continue;
                            int ret;
                            if (!DeviceIoControl(v, FSCTL_LOCK_VOLUME, null, 0, null, 0, out ret, IntPtr.Zero))
                            {
                                v.Dispose();
                                throw new IOException("Un fichier de la clé est ouvert par un autre programme. Fermez-le (Explorateur compris) et recommencez.");
                            }
                            DeviceIoControl(v, FSCTL_DISMOUNT_VOLUME, null, 0, null, 0, out ret, IntPtr.Zero);
                            locks.Add(v);
                        } while (FindNextVolume(find, name, name.Capacity));
                    }
                    finally { FindVolumeClose(find); }
                }

                SafeFileHandle h = Open(PhysicalPath(disk.Number), GENERIC_READ | GENERIC_WRITE);
                if (h.IsInvalid)
                    throw new IOException("Ouverture de la clé impossible : " + new Win32Exception(Marshal.GetLastWin32Error()).Message);
                int r;
                DeviceIoControl(h, IOCTL_DISK_DELETE_DRIVE_LAYOUT, null, 0, null, 0, out r, IntPtr.Zero);
                DeviceIoControl(h, IOCTL_DISK_UPDATE_PROPERTIES, null, 0, null, 0, out r, IntPtr.Zero);
                return new RawDisk(h, locks);
            }
            catch
            {
                foreach (SafeFileHandle l in locks) l.Dispose();
                throw;
            }
        }

        internal static void Rescan(SafeFileHandle h)
        {
            int r;
            DeviceIoControl(h, IOCTL_DISK_UPDATE_PROPERTIES, null, 0, null, 0, out r, IntPtr.Zero);
        }
    }

    /// <summary>Disque ouvert en ecriture brute, volumes verrouilles.</summary>
    public sealed class RawDisk : IDisposable
    {
        readonly SafeFileHandle handle;
        readonly List<SafeFileHandle> locks;
        public readonly FileStream Stream;

        internal RawDisk(SafeFileHandle h, List<SafeFileHandle> volumeLocks)
        {
            handle = h;
            locks = volumeLocks;
            Stream = new FileStream(h, FileAccess.ReadWrite, 1, false);
        }

        public void Dispose()
        {
            try { Stream.Flush(true); } catch (IOException) { }
            Disks.Rescan(handle);
            Stream.Dispose();
            foreach (SafeFileHandle l in locks) l.Dispose();
        }
    }
}
