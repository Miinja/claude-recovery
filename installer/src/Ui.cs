// The installer's look: palette, flat buttons, segmented selector and dark dialogs.
// Everything is drawn with GDI+, with no external dependency.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace CtrlZ
{
    public static class Theme
    {
        public static readonly Color Back = Color.FromArgb(22, 24, 31);
        public static readonly Color Surface = Color.FromArgb(32, 35, 45);
        public static readonly Color SurfaceHi = Color.FromArgb(44, 48, 61);
        public static readonly Color Line = Color.FromArgb(58, 63, 79);
        public static readonly Color Text = Color.FromArgb(236, 238, 244);
        public static readonly Color Muted = Color.FromArgb(150, 156, 175);
        public static readonly Color Accent = Color.FromArgb(108, 140, 255);
        public static readonly Color AccentHi = Color.FromArgb(134, 162, 255);
        public static readonly Color Ok = Color.FromArgb(61, 214, 140);
        public static readonly Color Danger = Color.FromArgb(240, 98, 98);
        public static readonly Color DangerHi = Color.FromArgb(246, 128, 128);

        public static float Scale = 1f;

        public static void Init()
        {
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) Scale = g.DpiX / 96f;
        }

        public static int S(int v) { return (int)Math.Round(v * Scale); }
        public static float S(float v) { return v * Scale; }

        public static Font F(float size) { return new Font("Segoe UI", size); }
        public static Font F(float size, FontStyle style) { return new Font("Segoe UI", size, style); }
        public static Font Semi(float size) { return new Font("Segoe UI Semibold", size); }

        public static GraphicsPath Round(RectangleF r, float radius)
        {
            float d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
            var p = new GraphicsPath();
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static void FillRound(Graphics g, Color c, RectangleF r, float radius)
        {
            using (GraphicsPath p = Round(r, radius))
            using (var b = new SolidBrush(c)) g.FillPath(b, p);
        }

        public static void StrokeRound(Graphics g, Color c, RectangleF r, float radius, float width)
        {
            using (GraphicsPath p = Round(r, radius))
            using (var pen = new Pen(c, width)) g.DrawPath(pen, p);
        }

        public const TextFormatFlags Center = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter
            | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine;
        public const TextFormatFlags Wrap = TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix;

        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        /// <summary>Dark title bar (Windows 10 2004 and later; no effect before).</summary>
        public static void DarkTitleBar(Form f)
        {
            try { int on = 1; DwmSetWindowAttribute(f.Handle, 20, ref on, 4); }
            catch (Exception) { }
        }
    }

    public enum ButtonKind { Accent, Ghost, Danger, Link }

    /// <summary>Flat button with rounded corners, usable from the keyboard.</summary>
    public sealed class FlatButton : Control
    {
        public ButtonKind Kind = ButtonKind.Ghost;
        bool hover, down;

        public FlatButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                   | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            SetStyle(ControlStyles.StandardDoubleClick, false);
            Cursor = Cursors.Hand;
            TabStop = true;
            Font = Theme.Semi(9.5f);
        }

        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { down = true; Focus(); Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

        protected override bool IsInputKey(Keys keyData)
        {
            return keyData == Keys.Enter || keyData == Keys.Space || base.IsInputKey(keyData);
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) { OnClick(EventArgs.Empty); e.Handled = true; }
            base.OnKeyDown(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Color parent = Parent != null ? Parent.BackColor : Theme.Back;
            g.Clear(parent);
            var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
            float radius = Theme.S(8f);
            Color fore = Theme.Text;

            if (Kind == ButtonKind.Link)
            {
                fore = !Enabled ? Theme.Line : hover ? Theme.AccentHi : Theme.Accent;
            }
            else if (!Enabled)
            {
                Theme.FillRound(g, Theme.Surface, r, radius);
                fore = Color.FromArgb(96, 101, 120);
            }
            else if (Kind == ButtonKind.Accent || Kind == ButtonKind.Danger)
            {
                Color fill = Kind == ButtonKind.Accent ? (hover ? Theme.AccentHi : Theme.Accent)
                                                       : (hover ? Theme.DangerHi : Theme.Danger);
                if (down) fill = ControlPaint.Dark(fill, 0.05f);
                Theme.FillRound(g, fill, r, radius);
                fore = Color.FromArgb(14, 16, 24);
            }
            else
            {
                Theme.FillRound(g, hover ? Theme.SurfaceHi : Theme.Surface, r, radius);
                Theme.StrokeRound(g, Theme.Line, r, radius, 1f);
            }
            if (Focused && ShowFocusCues && Kind != ButtonKind.Link)
                Theme.StrokeRound(g, Theme.Text, RectangleF.Inflate(r, -2, -2), radius - 2, 1f);

            var textRect = new Rectangle(Theme.S(10), 0, Width - Theme.S(20), Height);
            if (Kind == ButtonKind.Link) textRect = ClientRectangle;
            TextRenderer.DrawText(g, Text, Font, textRect, fore, Theme.Center);
        }
    }

    /// <summary>Selector with several positions (edition, language).</summary>
    public sealed class Segmented : Control
    {
        public string[] Items = new string[0];
        int selected;
        int hoverIndex = -1;
        public event EventHandler SelectedChanged;

        public Segmented()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                   | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            Cursor = Cursors.Hand;
            TabStop = true;
            Font = Theme.Semi(9.5f);
        }

        public int Selected
        {
            get { return selected; }
            set
            {
                if (value == selected || value < 0 || value >= Items.Length) return;
                selected = value;
                Invalidate();
                if (SelectedChanged != null) SelectedChanged(this, EventArgs.Empty);
            }
        }

        public void SetItems(params string[] items) { Items = items; Invalidate(); }

        int IndexAt(int x) { return Items.Length == 0 ? -1 : Math.Min(Items.Length - 1, Math.Max(0, x * Items.Length / Math.Max(1, Width))); }

        protected override void OnMouseMove(MouseEventArgs e) { int i = IndexAt(e.X); if (i != hoverIndex) { hoverIndex = i; Invalidate(); } base.OnMouseMove(e); }
        protected override void OnMouseLeave(EventArgs e) { hoverIndex = -1; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { Focus(); Selected = IndexAt(e.X); base.OnMouseDown(e); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override bool IsInputKey(Keys keyData) { return keyData == Keys.Left || keyData == Keys.Right || base.IsInputKey(keyData); }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Left) Selected = selected - 1;
            if (e.KeyCode == Keys.Right) Selected = selected + 1;
            base.OnKeyDown(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Parent != null ? Parent.BackColor : Theme.Back);
            var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
            float radius = Theme.S(8f);
            Theme.FillRound(g, Theme.Surface, r, radius);
            Theme.StrokeRound(g, Focused && ShowFocusCues ? Theme.Muted : Theme.Line, r, radius, 1f);
            if (Items.Length == 0) return;
            float w = (float)Width / Items.Length;
            for (int i = 0; i < Items.Length; i++)
            {
                var cell = new RectangleF(i * w + 3, 3, w - 6, Height - 6);
                Color fore = Theme.Muted;
                if (i == selected)
                {
                    Theme.FillRound(g, Enabled ? Theme.Accent : Theme.Line, cell, radius - 2);
                    fore = Enabled ? Color.FromArgb(14, 16, 24) : Theme.Muted;
                }
                else if (i == hoverIndex && Enabled) fore = Theme.Text;
                TextRenderer.DrawText(g, Items[i], Font, Rectangle.Round(cell), fore, Theme.Center);
            }
        }
    }

    /// <summary>Base of the dark dialogs: title, content, row of buttons.</summary>
    public class DarkDialog : Form
    {
        protected readonly Label Heading = new Label();
        protected int Pad;

        public DarkDialog(string title, int width, int height)
        {
            Pad = Theme.S(24);
            AutoScaleMode = AutoScaleMode.None;
            Font = Theme.F(9.5f);
            BackColor = Theme.Back;
            ForeColor = Theme.Text;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = false; ShowIcon = false;
            StartPosition = FormStartPosition.CenterParent;
            ClientSize = new Size(Theme.S(width), Theme.S(height));
            Text = "Ctrl-Z";
            Heading.Text = title;
            Heading.Font = Theme.Semi(13f);
            Heading.ForeColor = Theme.Text;
            Heading.UseMnemonic = false;
            Heading.SetBounds(Pad, Theme.S(20), ClientSize.Width - 2 * Pad, Theme.S(30));
            Controls.Add(Heading);
        }

        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Theme.DarkTitleBar(this); }

        /// <summary>Places the buttons at the bottom right, the first one being the rightmost.</summary>
        protected void PlaceButtons(params FlatButton[] buttons)
        {
            int x = ClientSize.Width - Pad;
            int h = Theme.S(38);
            foreach (FlatButton b in buttons)
            {
                int w = Math.Max(Theme.S(110), TextRenderer.MeasureText(b.Text, b.Font).Width + Theme.S(36));
                x -= w;
                b.SetBounds(x, ClientSize.Height - Pad - h, w, h);
                x -= Theme.S(10);
                Controls.Add(b);
            }
        }

        protected static FlatButton Button(string text, ButtonKind kind)
        {
            return new FlatButton { Text = text, Kind = kind };
        }
    }

    /// <summary>Message or question, instead of the system message boxes.</summary>
    public sealed class MessageDialog : DarkDialog
    {
        public MessageDialog(string title, string text, string yes, string no, ButtonKind yesKind)
            : base(title, 500, 200)
        {
            var body = new Label { Text = text, ForeColor = Theme.Muted, Font = Theme.F(10f), UseMnemonic = false };
            int width = ClientSize.Width - 2 * Pad;
            Size need = TextRenderer.MeasureText(text, body.Font, new Size(width, 0), Theme.Wrap | TextFormatFlags.TextBoxControl);
            body.SetBounds(Pad, Theme.S(62), width, need.Height + Theme.S(6));
            Controls.Add(body);
            ClientSize = new Size(ClientSize.Width, body.Bottom + Theme.S(28) + Theme.S(38) + Pad);

            FlatButton ok = Button(yes, yesKind);
            ok.Click += delegate { DialogResult = DialogResult.Yes; };
            if (no != null)
            {
                FlatButton cancel = Button(no, ButtonKind.Ghost);
                cancel.Click += delegate { DialogResult = DialogResult.No; };
                PlaceButtons(ok, cancel);
                cancel.TabIndex = 0; ok.TabIndex = 1;      // declining has the focus by default
            }
            else PlaceButtons(ok);
        }

        protected override bool ProcessDialogKey(Keys keyData)
        {
            if (keyData == Keys.Escape) { DialogResult = DialogResult.No; return true; }
            return base.ProcessDialogKey(keyData);
        }

        public static bool Ask(IWin32Window owner, string title, string text, string yes, string no, bool danger)
        {
            using (var d = new MessageDialog(title, text, yes, no, danger ? ButtonKind.Danger : ButtonKind.Accent))
                return d.ShowDialog(owner) == DialogResult.Yes;
        }

        public static void Show(IWin32Window owner, string title, string text)
        {
            using (var d = new MessageDialog(title, text, "OK", null, ButtonKind.Accent)) d.ShowDialog(owner);
        }
    }

    /// <summary>USB key selection.</summary>
    public sealed class DiskDialog : DarkDialog
    {
        readonly ListBox list = new ListBox();
        readonly Label empty = new Label();
        readonly FlatButton ok;
        public UsbDisk Selected;
        /// <summary>Disks shown instead of the real detection (screenshots).</summary>
        public List<UsbDisk> Demo;

        public DiskDialog()
            : base(L.T("Choisir la clé USB", "Select the USB key"), 520, 400)
        {
            var hint = new Label
            {
                Text = L.T("Seuls les disques USB sont proposés. La clé choisie sera entièrement effacée.",
                           "Only USB disks are listed. The key you select will be completely erased."),
                ForeColor = Theme.Muted, UseMnemonic = false
            };
            hint.SetBounds(Pad, Theme.S(54), ClientSize.Width - 2 * Pad, Theme.S(22));

            list.DrawMode = DrawMode.OwnerDrawFixed;
            list.ItemHeight = Theme.S(58);
            list.BorderStyle = BorderStyle.None;
            list.BackColor = Theme.Surface;
            list.IntegralHeight = false;
            list.SetBounds(Pad, Theme.S(88), ClientSize.Width - 2 * Pad, Theme.S(220));
            list.DrawItem += DrawDisk;
            list.SelectedIndexChanged += delegate { ok.Enabled = list.SelectedItem != null; };
            list.DoubleClick += delegate { Accept(); };

            empty.Text = L.T("Aucune clé USB détectée.\nBranchez-en une, puis cliquez sur Actualiser.",
                             "No USB key detected.\nPlug one in, then click Refresh.");
            empty.ForeColor = Theme.Muted; empty.BackColor = Theme.Surface;
            empty.TextAlign = ContentAlignment.MiddleCenter;
            empty.Bounds = list.Bounds;
            Controls.AddRange(new Control[] { hint, empty, list });

            ok = Button(L.T("Choisir", "Select"), ButtonKind.Accent);
            ok.Click += delegate { Accept(); };
            FlatButton cancel = Button(L.T("Annuler", "Cancel"), ButtonKind.Ghost);
            cancel.Click += delegate { DialogResult = DialogResult.Cancel; };
            PlaceButtons(ok, cancel);
            FlatButton refresh = Button(L.T("Actualiser", "Refresh"), ButtonKind.Ghost);
            refresh.SetBounds(Pad, ok.Top, Theme.S(120), ok.Height);
            refresh.Click += delegate { Reload(); };
            Controls.Add(refresh);
            Load += delegate { Reload(); };
        }

        void Accept()
        {
            Selected = list.SelectedItem as UsbDisk;
            if (Selected != null) DialogResult = DialogResult.OK;
        }

        void Reload()
        {
            list.Items.Clear();
            foreach (UsbDisk d in Demo ?? Disks.ListUsb()) list.Items.Add(d);
            empty.Visible = list.Items.Count == 0;
            list.Visible = !empty.Visible;
            if (list.Items.Count == 1) list.SelectedIndex = 0;
            ok.Enabled = list.SelectedItem != null;
        }

        void DrawDisk(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            var d = (UsbDisk)list.Items[e.Index];
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            bool sel = (e.State & DrawItemState.Selected) != 0;
            using (var b = new SolidBrush(Theme.Surface)) g.FillRectangle(b, e.Bounds);
            var card = new RectangleF(e.Bounds.X + 4, e.Bounds.Y + 4, e.Bounds.Width - 8, e.Bounds.Height - 8);
            if (sel)
            {
                Theme.FillRound(g, Theme.SurfaceHi, card, Theme.S(8f));
                Theme.StrokeRound(g, Theme.Accent, card, Theme.S(8f), 1.5f);
            }
            int x = e.Bounds.X + Theme.S(18);
            using (Font name = Theme.Semi(10.5f))
                TextRenderer.DrawText(g, d.Model, name, new Rectangle(x, e.Bounds.Y + Theme.S(9), e.Bounds.Width - Theme.S(36), Theme.S(22)),
                    Theme.Text, TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            string info = UsbDisk.FormatSize(d.Size) + "  ·  " + L.T("disque ", "disk ") + d.Number;
            if (d.Size > MainForm.BigDisk) info += "  ·  " + L.T("très grand pour une clé", "very large for a key");
            TextRenderer.DrawText(g, info, Font, new Rectangle(x, e.Bounds.Y + Theme.S(31), e.Bounds.Width - Theme.S(36), Theme.S(20)),
                d.Size > MainForm.BigDisk ? Theme.Danger : Theme.Muted, TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
    }

    /// <summary>Business edition settings, written to the key.</summary>
    public sealed class KeySettings
    {
        public string Company = "", KeyId = "", LogUrl = "", Token = "", GitUrl = "";

        public bool Complete { get { return Validate() == null; } }

        /// <summary>Error message, or null when the settings are valid.</summary>
        public string Validate()
        {
            if (!Regex.IsMatch(KeyId, "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"))
                return L.T("Le nom de la clé est obligatoire : lettres, chiffres, point, tiret ou souligné (ex. cle01).",
                           "The key name is required: letters, digits, dot, dash or underscore (e.g. key01).");
            if (LogUrl.Length > 0 && !Regex.IsMatch(LogUrl, "^https?://[^\\s]+$"))
                return L.T("L'adresse du serveur de journaux doit commencer par https://",
                           "The log server address must start with https://");
            if (LogUrl.Length > 0 && Token.Length == 0)
                return L.T("Un serveur de journaux est indiqué : le jeton de la clé est obligatoire.",
                           "A log server is set: the key token is required.");
            if (GitUrl.Length > 0 && !Regex.IsMatch(GitUrl, "^https?://[^\\s]+$"))
                return L.T("L'adresse du dépôt de mise à jour doit commencer par https://",
                           "The update repository address must start with https://");
            return null;
        }
    }

    public sealed class SettingsDialog : DarkDialog
    {
        readonly TextBox[] boxes = new TextBox[5];
        readonly Label message = new Label();
        readonly FlatButton test;
        public readonly KeySettings Result = new KeySettings();

        public static string ServerGuideUrl
        {
            get { return "https://github.com/" + Releases.Repo + "/blob/main/server/" + L.T("README.fr.md", "README.md"); }
        }

        public SettingsDialog(KeySettings current)
            : base(L.T("Réglages de l'édition entreprise", "Business edition settings"), 600, 690)
        {
            string[] labels = {
                L.T("Nom de l'entreprise", "Company name"),
                L.T("Nom de cette clé", "Name of this key"),
                L.T("Serveur de journaux", "Log server"),
                L.T("Jeton de la clé", "Key token"),
                L.T("Dépôt de mise à jour", "Update repository") };
            string[] tags = {
                L.T("facultatif", "optional"), L.T("obligatoire", "required"), L.T("facultatif", "optional"),
                L.T("obligatoire avec un serveur", "required with a server"), L.T("facultatif", "optional") };
            string[] help = {
                L.T("Le nom de votre atelier ou de votre société. Il sert seulement à identifier à qui appartient la clé.",
                    "The name of your workshop or company. It only identifies who the key belongs to."),
                L.T("Un nom que vous choisissez pour reconnaître cette clé dans les journaux, par exemple cle01. Prenez le même nom que sur la ligne de cette clé dans tokens.txt.",
                    "A name you choose to recognise this key in the logs, for example key01. Use the same name as on this key's line in tokens.txt."),
                L.T("L'adresse de votre récepteur de journaux : https:// suivi de la valeur LOGS_DOMAIN du fichier server/.env de votre serveur. Vide : le journal reste sur la clé.",
                    "The address of your log receiver: https:// followed by the LOGS_DOMAIN value from server/.env on your server. Empty: logs stay on the key."),
                L.T("Le jeton écrit sur la ligne de cette clé dans server/tokens.txt (nom, puis jeton). Pour en créer un sur le serveur : openssl rand -hex 32",
                    "The token on this key's line in server/tokens.txt (name, then token). To create one on the server: openssl rand -hex 32"),
                L.T("Laissez vide : la clé se met à jour depuis le dépôt GitHub du projet. À remplir seulement si l'entreprise héberge sa propre copie (adresse https du dépôt).",
                    "Leave empty: the key updates from the project's GitHub repository. Fill in only if the company hosts its own copy (https address of the repository).") };
            string[] values = { current.Company, current.KeyId, current.LogUrl, current.Token, current.GitUrl };
            int width = ClientSize.Width - 2 * Pad;
            for (int i = 0; i < 5; i++)
            {
                int y = Theme.S(64 + i * 98);
                var label = new Label { Text = labels[i], ForeColor = Theme.Text, Font = Theme.Semi(9.5f), UseMnemonic = false };
                label.SetBounds(Pad, y, Theme.S(260), Theme.S(20));
                var tag = new Label { Text = tags[i], ForeColor = i == 1 ? Theme.Accent : Theme.Muted, Font = Theme.F(8.5f), TextAlign = ContentAlignment.TopRight, UseMnemonic = false };
                tag.SetBounds(Pad + Theme.S(260), y + Theme.S(2), width - Theme.S(260), Theme.S(18));
                var frame = new Panel { BackColor = Theme.Surface };
                frame.SetBounds(Pad, y + Theme.S(24), width, Theme.S(32));
                boxes[i] = new TextBox { BorderStyle = BorderStyle.None, BackColor = Theme.Surface, ForeColor = Theme.Text, Font = Theme.F(10.5f), Text = values[i] };
                boxes[i].SetBounds(Theme.S(10), Theme.S(6), width - Theme.S(20), Theme.S(22));
                frame.Controls.Add(boxes[i]);
                var hint = new Label { Text = help[i], ForeColor = Theme.Muted, Font = Theme.F(8.5f), UseMnemonic = false };
                hint.SetBounds(Pad, y + Theme.S(60), width, Theme.S(34));
                Controls.AddRange(new Control[] { label, tag, frame, hint });
            }
            boxes[3].UseSystemPasswordChar = true;

            var guide = new FlatButton { Kind = ButtonKind.Link, Font = Theme.F(9f),
                Text = L.T("Guide de mise en place du serveur (ouvre le navigateur)", "Server setup guide (opens the browser)") };
            guide.SetBounds(Pad, Theme.S(556), Theme.S(340), Theme.S(22));
            guide.Click += delegate { try { System.Diagnostics.Process.Start(ServerGuideUrl); } catch (Exception) { } };
            Controls.Add(guide);

            message.UseMnemonic = false;
            message.SetBounds(Pad, Theme.S(582), width, Theme.S(36));
            Controls.Add(message);

            FlatButton ok = Button(L.T("Enregistrer", "Save"), ButtonKind.Accent);
            ok.Click += delegate { Accept(); };
            FlatButton cancel = Button(L.T("Annuler", "Cancel"), ButtonKind.Ghost);
            cancel.Click += delegate { DialogResult = DialogResult.Cancel; };
            PlaceButtons(ok, cancel);
            test = Button(L.T("Tester le serveur", "Test the server"), ButtonKind.Ghost);
            test.SetBounds(Pad, ok.Top, Theme.S(170), ok.Height);
            test.Click += async delegate { await TestServer(); };
            Controls.Add(test);
        }

        void Say(string text, Color color) { message.ForeColor = color; message.Text = text; }

        void Collect()
        {
            Result.Company = boxes[0].Text.Trim(); Result.KeyId = boxes[1].Text.Trim(); Result.LogUrl = boxes[2].Text.Trim().TrimEnd('/');
            Result.Token = boxes[3].Text.Trim(); Result.GitUrl = boxes[4].Text.Trim();
        }

        void Accept()
        {
            Collect();
            string problem = Result.Validate();
            if (problem != null) { Say(problem, Theme.Danger); return; }
            DialogResult = DialogResult.OK;
        }

        /// <summary>Queries the receiver: reachable? token accepted? Writes nothing to it.</summary>
        async System.Threading.Tasks.Task TestServer()
        {
            Collect();
            string url = Result.LogUrl, token = Result.Token;
            if (!Regex.IsMatch(url, "^https?://[^\\s]+$"))
            {
                Say(L.T("Indiquez d'abord l'adresse du serveur de journaux (https://…).", "Enter the log server address first (https://…)."), Theme.Danger);
                return;
            }
            test.Enabled = false;
            Say(L.T("Test en cours…", "Testing…"), Theme.Muted);
            string result = await System.Threading.Tasks.Task.Run(delegate { return Probe(url, token); });
            if (IsDisposed) return;
            test.Enabled = true;
            Say(result.Substring(1), result[0] == '+' ? Theme.Ok : Theme.Danger);
        }

        /// <summary>Result prefixed with + (all good) or - (problem).</summary>
        public static string Probe(string url, string token)
        {
            try
            {
                System.Net.ServicePointManager.SecurityProtocol = (System.Net.SecurityProtocolType)3072;   // TLS 1.2
                var health = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url + "/healthz");
                health.Timeout = 8000;
                using (health.GetResponse()) { }
                if (token.Length == 0)
                    return "-" + L.T("Serveur joignable. Renseignez le jeton de la clé pour le vérifier aussi.", "Server reachable. Enter the key token to check it too.");
                var post = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url + "/api/logs");
                post.Method = "POST"; post.Timeout = 8000; post.ContentLength = 0;
                post.ContentType = "application/x-ndjson";
                post.Headers["Authorization"] = "Bearer " + token;
                using (post.GetResponse()) { }
                return "+" + L.T("Serveur joignable et jeton accepté.", "Server reachable and token accepted.");
            }
            catch (System.Net.WebException e)
            {
                var response = e.Response as System.Net.HttpWebResponse;
                if (response != null && (int)response.StatusCode == 401)
                    return "-" + L.T("Serveur joignable, mais ce jeton est refusé : vérifiez la ligne de la clé dans tokens.txt.",
                                     "Server reachable, but this token is refused: check the key's line in tokens.txt.");
                if (response != null)
                    return "-" + L.T("Le serveur répond avec une erreur ", "The server answers with error ") + (int)response.StatusCode
                               + L.T(" : est-ce bien l'adresse du récepteur de journaux ?", ": is this really the log receiver's address?");
                if (e.Status == System.Net.WebExceptionStatus.TrustFailure)
                    return "-" + L.T("Certificat du serveur non reconnu par ce PC (autorité interne ?). La clé, elle, l'acceptera si son image contient le certificat.",
                                     "The server's certificate is not trusted by this PC (internal authority?). The key will accept it if its image includes the certificate.");
                return "-" + L.T("Serveur injoignable depuis ce PC : ", "Server unreachable from this PC: ") + e.Message;
            }
            catch (Exception e)
            {
                return "-" + L.T("Test impossible : ", "Test failed: ") + e.Message;
            }
        }

        protected override bool ProcessDialogKey(Keys keyData)
        {
            if (keyData == Keys.Enter) { Accept(); return true; }
            if (keyData == Keys.Escape) { DialogResult = DialogResult.Cancel; return true; }
            return base.ProcessDialogKey(keyData);
        }
    }
}
