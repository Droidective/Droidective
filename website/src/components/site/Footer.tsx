import { DOWNLOAD_URL, GITHUB_URL, RELEASES_URL } from "@/lib/content"

const columns = [
  {
    title: "Product",
    links: [
      { label: "Download", href: DOWNLOAD_URL },
      { label: "Releases", href: RELEASES_URL },
      { label: "Changelog", href: "/changelog/" },
    ],
  },
  {
    title: "Guides",
    links: [
      { label: "Android developers", href: "/for-android-developers.html" },
      { label: "iOS developers", href: "/for-ios-developers.html" },
      { label: "React Native", href: "/react-native-debugger.html" },
      { label: "QA & testers", href: "/for-qa-and-testers.html" },
      { label: "Security / pentest", href: "/for-security-testers.html" },
    ],
  },
  {
    title: "Resources",
    links: [
      { label: "Blog", href: "/blog/" },
      { label: "GitHub", href: GITHUB_URL },
      { label: "Issues", href: `${GITHUB_URL}/issues` },
      { label: "License (MIT)", href: `${GITHUB_URL}/blob/main/LICENSE` },
      { label: "Privacy", href: "/privacy.html" },
    ],
  },
  {
    title: "More",
    links: [
      { label: "scrcpy GUI for Mac", href: "/scrcpy-gui-mac.html" },
      { label: "For support teams", href: "/for-support-teams.html" },
    ],
  },
]

export function Footer() {
  return (
    <footer className="border-t border-white/[0.04] px-6 pt-16 pb-18 text-sm text-muted">
      <div className="mx-auto max-w-[1120px]">
        <div className="grid grid-cols-[1.4fr_1fr_1fr_1fr] gap-10 max-[940px]:grid-cols-2 max-[940px]:gap-8 max-[620px]:grid-cols-1">
          <div>
            <a href="#top" className="mb-4 flex items-center gap-2.5 font-bold text-text">
              <img src="/assets/icon-light-64.png" alt="" width={24} height={24} loading="lazy" decoding="async" className="rounded-[6px]" />
              Droidective
            </a>
            <p className="mt-3 max-w-[30ch] text-[13px] leading-[1.75] text-faint/80">
              A native macOS command palette for Android &amp; React Native debugging. Free and open source.
            </p>
          </div>
          {columns.map((col) => (
            <div key={col.title}>
              <p className="mb-3.5 font-mono text-[10.5px] tracking-[0.08em] text-faint/60 uppercase">{col.title}</p>
              <ul className="m-0 list-none space-y-2.5 p-0">
                {col.links.map((link) => (
                  <li key={link.label}>
                    <a
                      href={link.href}
                      className="text-[13px] text-muted/70 transition-colors duration-200 hover:text-green"
                    >
                      {link.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <div className="mt-14 border-t border-white/[0.04] pt-6">
          <p className="max-w-[76ch] text-[11.5px] leading-[1.75] text-faint/60">
            Made by Rohindh R · MIT licensed · © 2026. Not affiliated with Google or the Android Open Source Project.
            Android is a trademark of Google LLC. scrcpy, adb, ffmpeg, and the Android emulator are independent
            projects with their own licenses; Droidective bundles the scrcpy server and a static ffmpeg build, and
            shells out to adb and the Android emulator.
          </p>
        </div>
      </div>
    </footer>
  )
}
