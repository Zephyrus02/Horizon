import driveLogo from '../assets/drive_64.png'
import dropboxLogo from '../assets/dropbox_64.png'
import onedriveLogo from '../assets/onedrive_64.png'
import Icon from './Icon'

const accounts = [
  { name: 'Google Drive', path: '~/GDrive', logo: driveLogo, status: 'Connected', on: true },
  { name: 'Dropbox', path: '~/Dropbox', logo: dropboxLogo, status: 'Syncing 3 files', on: true },
  { name: 'OneDrive', path: '~/OneDrive', logo: onedriveLogo, status: 'Disconnected', on: false },
]

// A static recreation of the Horizon menu-bar popover.
export default function MenuBarMock() {
  return (
    <div className="mock" aria-label="Preview of the Horizon menu-bar panel" role="img">
      <div className="mock__menubar">
        <span className="mock__apple" />
        <span className="mock__menu">Finder</span>
        <span className="mock__menu mock__menu--dim">File</span>
        <span className="mock__menu mock__menu--dim">Edit</span>
        <span className="mock__menu mock__menu--dim">View</span>
        <span className="mock__spacer" />
        <span className="mock__tray mock__tray--active">
          <img src="/logo.png" alt="" width="14" height="14" />
        </span>
        <span className="mock__clock">Sat 9:41</span>
      </div>

      <div className="mock__desktop">
        <div className="mock__finder">
          <div className="mock__finder-bar">
            <i />
            <i />
            <i />
            <span>GDrive</span>
          </div>
          <div className="mock__finder-body">
            <aside>
              <small>Locations</small>
              <p className="is-active">
                <Icon name="disk" size={13} /> GDrive
              </p>
              <p>
                <Icon name="disk" size={13} /> Dropbox
              </p>
              <small>Favourites</small>
              <p>Desktop</p>
              <p>Documents</p>
            </aside>
            <div className="mock__files">
              {['Footage', 'Projects', 'Invoices', 'Q3 Review.key', 'trailer_4k.mov', 'notes.md'].map(
                (f, i) => (
                  <div key={f} className="mock__file" style={{ '--i': i }}>
                    <span className={i < 3 ? 'mock__folder' : 'mock__doc'} />
                    {f}
                  </div>
                ),
              )}
            </div>
          </div>
        </div>

        <div className="mock__panel">
          <div className="mock__panel-head">
            <strong>
              <img src="/logo.png" alt="" width="14" height="14" /> Horizon
            </strong>
            <span className="status">
              <span className="status__dot" /> 2 connected
            </span>
          </div>
          {accounts.map((a) => (
            <div key={a.name} className="mock__account">
              <img src={a.logo} alt="" width="26" height="26" />
              <div>
                <b>{a.name}</b>
                <small>
                  {a.path} · {a.status}
                </small>
              </div>
              <span className={`switch ${a.on ? 'switch--on' : ''}`} />
            </div>
          ))}
          <div className="mock__transfer">
            <div className="mock__transfer-row">
              <span>Uploading trailer_4k.mov</span>
              <span>148 MB/s</span>
            </div>
            <div className="mock__bar">
              <span />
            </div>
          </div>
          <div className="mock__panel-foot">
            <span>Open in Finder</span>
            <span>Settings…</span>
          </div>
        </div>
      </div>
    </div>
  )
}
