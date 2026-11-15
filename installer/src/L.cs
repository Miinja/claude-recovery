// Interface language: French or English, chosen in the window.
using System.Globalization;

namespace ClaudeRecovery
{
    public static class L
    {
        /// <summary>"fr" or "en". Defaults to the language of Windows.</summary>
        public static string Lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr" ? "fr" : "en";

        public static string T(string fr, string en)
        {
            return Lang == "fr" ? fr : en;
        }
    }
}
