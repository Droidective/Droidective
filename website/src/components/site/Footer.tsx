import { DOWNLOAD_URL, GITHUB_URL, RELEASES_URL } from "@/lib/content"

/** One inline band rather than four stacked columns. Labels are shortened so
 *  the whole set still fits a single line at desktop widths — every guide page
 *  is kept, because those internal links carry the site's SEO. */
const links = [
  { label: "Download", href: DOWNLOAD_URL },
  { label: "Releases", href: RELEASES_URL },
  { label: "Changelog", href: "/changelog/" },
  { label: "Blog", href: "/blog/" },
  { label: "GitHub", href: GITHUB_URL },
  { label: "Issues", href: `${GITHUB_URL}/issues` },
  { label: "MIT", href: `${GITHUB_URL}/blob/main/LICENSE` },
  { label: "Privacy", href: "/privacy.html" },
  { label: "Android", href: "/for-android-developers.html" },
  { label: "iOS", href: "/for-ios-developers.html" },
  { label: "React Native", href: "/react-native-debugger.html" },
  { label: "QA", href: "/for-qa-and-testers.html" },
  { label: "Security", href: "/for-security-testers.html" },
  { label: "Support", href: "/for-support-teams.html" },
  { label: "scrcpy GUI", href: "/scrcpy-gui-mac.html" },
]

export function Footer() {
  return (
    <footer className="border-t border-white/[0.06] bg-white/[0.012] px-6 pt-14 pb-12 max-[620px]:pt-11 max-[620px]:pb-10">
      <div className="mx-auto max-w-[1120px]">
        <div className="flex items-center gap-x-8 gap-y-5 max-[940px]:flex-col max-[940px]:items-start">
          <a
            href="#top"
            className="group/f flex shrink-0 items-center gap-2.5 text-[16px] font-bold tracking-[-0.02em] text-text"
          >
            <img
              src="/assets/icon-light-64.png"
              alt=""
              width={30}
              height={30}
              loading="lazy"
              decoding="async"
              className="size-7.5 rounded-[9px] ring-1 ring-white/12 transition-transform duration-300 group-hover/f:scale-[1.04]"
            />
            Droidective
          </a>

          <nav className="flex flex-wrap items-center gap-x-3.5 gap-y-2.5">
            {links.map((l) => (
              <a
                key={l.label}
                href={l.href}
                className="text-[13px] whitespace-nowrap text-muted/80 transition-colors duration-200 hover:text-green"
              >
                {l.label}
              </a>
            ))}
          </nav>
        </div>

        <p className="mt-9 max-w-[92ch] border-t border-white/[0.05] pt-7 text-[12px] leading-[1.75] text-faint/65">
          <span className="font-mono text-muted/70">MIT · © 2026 Rohindh R</span>
          <br />
          Not affiliated with Google or the Android Open Source Project. Android is a trademark of Google LLC.
          scrcpy, adb, ffmpeg, and the Android emulator are independent projects under their own licenses.
        </p>
      </div>
    </footer>
  )
}
