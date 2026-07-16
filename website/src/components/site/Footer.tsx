import { footerLinks } from "@/lib/content"

export function Footer() {
  return (
    <footer className="border-t border-border px-6 pt-12 pb-16 text-sm text-muted">
      <div className="mx-auto max-w-[1120px]">
        <div className="flex flex-wrap items-center justify-between gap-5.5">
          <a href="#top" className="flex items-center gap-2.75 font-bold text-text">
            <img src="/assets/icon-64.png" alt="" width={26} height={26} loading="lazy" decoding="async" className="rounded-md" />
            Droidective
          </a>
          <div className="flex flex-wrap gap-5.5">
            {footerLinks.map((link) => (
              <a
                key={link.label}
                href={link.href}
                className="-my-2 py-2 transition-colors duration-150 hover:text-green"
              >
                {link.label}
              </a>
            ))}
          </div>
        </div>
        <p className="mt-5.5 max-w-[76ch] text-xs leading-[1.7] text-faint">
          Made by Rohindh R · MIT licensed · © 2026. Not affiliated with Google or the Android Open Source Project.
          Android is a trademark of Google LLC. scrcpy, adb, ffmpeg, and the Android emulator are independent
          projects with their own licenses; Droidective bundles the scrcpy server and a static ffmpeg build, and
          shells out to adb and the Android emulator.
        </p>
      </div>
    </footer>
  )
}
