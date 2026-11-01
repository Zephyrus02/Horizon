import LegalPage from './LegalPage'
import { REPO_URL } from '../links'

export default function Privacy() {
  return (
    <LegalPage title="Privacy Policy" updated="November 1, 2026">
      <p>
        Horizon is a free, open-source macOS menu-bar app that mounts your Google Drive in Finder.
        It runs entirely on your Mac. This policy explains what that means for your data.
      </p>

      <h2>The short version</h2>
      <ul>
        <li>Horizon does not have a server. We do not receive, store, or sell your files or personal data.</li>
        <li>Your files travel directly between your Mac and Google Drive.</li>
        <li>Horizon does not include analytics, advertising, or tracking.</li>
      </ul>

      <h2>What Horizon accesses</h2>
      <p>
        When you connect Google Drive, Horizon (through <code>rclone</code>) asks Google for permission
        to read and write files in your Drive so they can appear in Finder. Your sign-in credentials
        and access tokens are stored locally on your Mac, in the rclone configuration. They are never
        sent to us.
      </p>

      <h2>Local storage</h2>
      <p>
        To make streaming and editing fast, Horizon keeps a temporary cache of file data on your disk
        at <code>~/Library/Caches/Horizon</code>. You can delete this folder at any time. Edited files
        are uploaded back to Google Drive in the background.
      </p>

      <h2>Third parties</h2>
      <p>
        Your use of Google Drive is governed by Google's own terms and privacy policy. Horizon relies
        on the open-source <code>rclone</code> project to communicate with Google. We are not
        affiliated with Google or rclone.
      </p>

      <h2>This website</h2>
      <p>
        The Horizon website is a static page. It does not use cookies or collect personal information
        itself. Downloads and the source code are hosted on GitHub, which has its own privacy practices.
      </p>

      <h2>Removing your data</h2>
      <p>
        To disconnect, quit Horizon and remove its rclone configuration and cache folder. You can
        also revoke Horizon's access at any time from your Google Account's security settings.
      </p>

      <h2>Changes</h2>
      <p>
        If this policy changes, we will update the date above. Because Horizon is open source, you can
        review exactly what the app does in the{' '}
        <a href={REPO_URL}>source code</a>.
      </p>

      <h2>Contact</h2>
      <p>
        Questions? Open an issue on <a href={`${REPO_URL}/issues`}>GitHub</a>.
      </p>
    </LegalPage>
  )
}
