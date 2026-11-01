import LegalPage from './LegalPage'
import { REPO_URL } from '../links'

export default function Terms() {
  return (
    <LegalPage title="Terms of Service" updated="November 1, 2026">
      <p>
        By downloading or using Horizon, you agree to these terms. If you do not agree, please do not
        use the app.
      </p>

      <h2>License</h2>
      <p>
        Horizon is open-source software released under the MIT License. You may use, copy, modify, and
        distribute it under the terms of that license, available in the{' '}
        <a href={REPO_URL}>project repository</a>.
      </p>

      <h2>Your account and files</h2>
      <p>
        You are responsible for your Google account, the files in your Drive, and for complying with
        Google's terms of service. Horizon only acts on your behalf when you connect your account.
      </p>

      <h2>Acceptable use</h2>
      <p>
        You agree not to use Horizon to break the law, infringe on others' rights, or violate the
        terms of any service you connect to it.
      </p>

      <h2>Backups and data safety</h2>
      <p>
        Horizon caches data locally and uploads changes in the background. Unmounting, quitting, losing
        network access, or a crash before an upload finishes may leave changes unsynced. Keep backups
        of anything important.
      </p>

      <h2>No warranty</h2>
      <p>
        Horizon is provided "as is", without warranty of any kind, express or implied, including
        fitness for a particular purpose and non-infringement. We do not guarantee that it will be
        uninterrupted or error-free.
      </p>

      <h2>Limitation of liability</h2>
      <p>
        To the fullest extent permitted by law, the authors and contributors are not liable for any
        claim, damages, or data loss arising from your use of Horizon.
      </p>

      <h2>Third-party services</h2>
      <p>
        Horizon works with Google Drive and <code>rclone</code>. We are not affiliated with or
        endorsed by Google or the rclone project, and their own terms apply to your use of them.
      </p>

      <h2>Changes</h2>
      <p>
        We may update these terms from time to time. Continued use after a change means you accept the
        updated terms.
      </p>

      <h2>Contact</h2>
      <p>
        Questions? Open an issue on <a href={`${REPO_URL}/issues`}>GitHub</a>.
      </p>
    </LegalPage>
  )
}
