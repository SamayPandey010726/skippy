import { lazy, Suspense, useEffect, useMemo, useRef, useState, type DragEvent, type FormEvent, type KeyboardEvent } from 'react'
import {
  Accessibility,
  Archive,
  ArrowLeft,
  ArrowDown,
  Check,
  ChevronRight,
  Clipboard,
  Copy,
  FileImage,
  FileSpreadsheet,
  FileText,
  Filter,
  FolderInput,
  Grid2X2,
  Layers3,
  Link2,
  List,
  Monitor,
  PackagePlus,
  Play,
  Search,
  ShieldCheck,
  Sparkles,
  Trash2,
  Users,
  WandSparkles,
} from 'lucide-react'
import SpotlightCard from './components/SpotlightCard'

const ParcelWorld = lazy(() => import('./components/ParcelWorld'))

type FileKind = 'image' | 'sheet' | 'document' | 'video' | 'text'
type ParcelFile = { id: number; name: string; kind: FileKind; size: string }
type Clip = { id: number; title: string; detail: string; kind: 'text' | 'link' | 'file' }
type ViewMode = 'grid' | 'list' | 'dial'
type Panel = 'clipboard' | 'parcels' | 'search' | null

const initialFiles: ParcelFile[] = [
  { id: 1, name: 'Campaign brief.pdf', kind: 'document', size: '2.4 MB' },
  { id: 2, name: 'Launch metrics.xlsx', kind: 'sheet', size: '814 KB' },
  { id: 3, name: 'Hero artwork.png', kind: 'image', size: '4.8 MB' },
  { id: 4, name: 'Product demo.mov', kind: 'video', size: '18.3 MB' },
]

const initialClips: Clip[] = [
  { id: 1, title: 'Launch copy', detail: 'Everything in motion, within reach.', kind: 'text' },
  { id: 2, title: 'Design review', detail: 'https://example.com/review/parcel', kind: 'link' },
]

const kindIcons = {
  image: FileImage,
  sheet: FileSpreadsheet,
  document: FileText,
  video: Play,
  text: FileText,
}

const features = [
  { icon: Layers3, tag: 'Quiver', title: 'Hover to unfold your pinned arrows.', body: 'Choose a menu-bar mark, a notch, a floating icon, a screen edge or the Dock. Click an arrow for its tool panel.' },
  { icon: FolderInput, tag: 'Shelf', title: 'Catch anything without changing windows.', body: 'Drag files, paste images or text, or summon Skippy from the keyboard. Your current work stays exactly where it is.' },
  { icon: WandSparkles, tag: 'Convert', title: 'Shift-drag into a contextual conversion wheel.', body: 'Images, PDFs, Word, text and spreadsheets turn into compatible formats, with each result saved safely inside Skippy.' },
  { icon: Clipboard, tag: 'Clipboard', title: 'A visual clipboard that remembers the useful parts.', body: 'Search text, links, images and files. Drag them back out as their native content instead of hunting through old windows.' },
  { icon: Link2, tag: 'Links', title: 'Shorten a link where you already copied it.', body: 'Right-click a URL, shorten it, and the result becomes a fresh clipboard item ready to paste.' },
  { icon: Archive, tag: 'Pack', title: 'Pack once. Send anywhere.', body: 'Build a standards-based ZIP, remove common Mac clutter, add a note and drag the finished parcel into a compatible app.' },
  { icon: Sparkles, tag: 'Prepare', title: 'Prepare images, video and visible text.', body: 'Resize or recompress media as new copies, and use local OCR to pull text from images without touching the original.' },
]

const shortcuts = [
  ['⌃ ⌥ ⌘ P', 'Show or hide the shelf'],
  ['⇧ + drag', 'Open the conversion wheel'],
  ['⌘ ⇧ V', 'Capture clipboard content'],
  ['/', 'Search the open parcel'],
  ['⇧ /', 'Open filters'],
  ['⌘ P', 'Pack the current parcel'],
  ['⌘ C', 'Copy the focused item'],
  ['Return', 'Open the focused item'],
]

function App() {
  const [waitlistOpen, setWaitlistOpen] = useState(false)
  if (window.location.pathname === '/pricing') return <PricingPage />

  return (
    <div className="site-shell">
      <Header onWaitlist={() => setWaitlistOpen(true)} />
      <main id="main">
        <CinematicExperience onWaitlist={() => setWaitlistOpen(true)} />
        <InteractiveDemo />
        <Proof />
        <FeatureGrid />
        <WaysToWorkSection />
        <AccessibilitySection />
        <FinalCta onWaitlist={() => setWaitlistOpen(true)} />
      </main>
      <Footer />
      {waitlistOpen && <WaitlistDialog close={() => setWaitlistOpen(false)} />}
    </div>
  )
}

function Header({ onWaitlist }: { onWaitlist: () => void }) {
  return (
    <header className="topbar">
      <a className="brand" href="#top" aria-label="Skippy home">
        <img src="/media/parcel-icon.png" alt="" />
        <span>Skippy</span>
      </a>
      <nav aria-label="Primary navigation">
        <a href="/#top">The journey</a><a href="/#try">Try it</a><a href="/#features">Features</a><a href="/pricing">Pricing</a>
      </nav>
      <button className="button button-small" type="button" onClick={onWaitlist}>Join waitlist <ChevronRight size={15} /></button>
    </header>
  )
}

const cinematicScenes = [
  { number: '00', label: 'The quiver', title: <>One quiver.<br /><em>Everyday tools.</em></>, body: 'Hover over Skippy to unfold your pinned arrows. Open the File Shelf, a quick note or a focus timer right where you are working.' },
  { number: '01', label: 'Catch', title: <>Anything in.<br /><em>No detour.</em></>, body: 'Drag, paste, share or use the shortcut. Skippy appears exactly when you need it, without pulling you away from your work.' },
  { number: '02', label: 'Prepare', title: <>Change the thing.<br /><em>Keep the flow.</em></>, body: 'Convert formats, resize media, shorten links and extract visible text while the item stays inside the parcel.' },
  { number: '03', label: 'Pack', title: <>Loose pieces become<br /><em>one clean handoff.</em></>, body: 'Your files fold into a standards-based ZIP with the compression, naming and cleanup you prefer.' },
  { number: '04', label: 'Send', title: <>Drop it anywhere.<br /><em>Done.</em></>, body: 'The finished parcel travels into Mail, Messages, WhatsApp, Telegram and other compatible Mac apps.' },
]

function CinematicExperience({ onWaitlist }: { onWaitlist: () => void }) {
  const sectionRef = useRef<HTMLElement>(null)
  const progressRef = useRef(0)
  const sceneRef = useRef(0)
  const [scene, setScene] = useState(0)
  const [autoTour, setAutoTour] = useState(false)
  const reducedMotion = typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches

  useEffect(() => {
    let frame = 0
    const update = () => {
      const section = sectionRef.current
      if (!section) return
      const bounds = section.getBoundingClientRect()
      const distance = Math.max(1, bounds.height - window.innerHeight)
      const value = Math.max(0, Math.min(1, -bounds.top / distance))
      progressRef.current = value
      const nextScene = Math.min(cinematicScenes.length - 1, Math.floor(value * cinematicScenes.length))
      if (nextScene !== sceneRef.current) { sceneRef.current = nextScene; setScene(nextScene) }
      frame = 0
    }
    const requestUpdate = () => { if (!frame) frame = window.requestAnimationFrame(update) }
    update()
    window.addEventListener('scroll', requestUpdate, { passive: true })
    window.addEventListener('resize', requestUpdate)
    return () => { window.cancelAnimationFrame(frame); window.removeEventListener('scroll', requestUpdate); window.removeEventListener('resize', requestUpdate) }
  }, [])

  useEffect(() => {
    if (!autoTour || reducedMotion) return
    let frame = 0
    let previous = performance.now()
    const tick = (now: number) => {
      const section = sectionRef.current
      if (!section) return
      const bottom = section.offsetTop + section.offsetHeight - window.innerHeight
      if (window.scrollY >= bottom - 2) { setAutoTour(false); return }
      window.scrollBy(0, Math.min(4.5, (now - previous) * 0.075))
      previous = now
      frame = window.requestAnimationFrame(tick)
    }
    const stop = () => setAutoTour(false)
    window.addEventListener('wheel', stop, { passive: true, once: true })
    window.addEventListener('touchstart', stop, { passive: true, once: true })
    frame = window.requestAnimationFrame(tick)
    return () => {
      window.cancelAnimationFrame(frame)
      window.removeEventListener('wheel', stop)
      window.removeEventListener('touchstart', stop)
    }
  }, [autoTour, reducedMotion])

  const jumpToScene = (index: number) => {
    const section = sectionRef.current
    if (!section) return
    const distance = section.offsetHeight - window.innerHeight
    window.scrollTo({ top: section.offsetTop + distance * (index / (cinematicScenes.length - 1)), behavior: reducedMotion ? 'auto' : 'smooth' })
    setAutoTour(false)
  }

  return <section className={`cinematic scene-${scene}`} id="top" ref={sectionRef}>
    <div className="cinematic-sticky">
      <div className="cinematic-viewport">
        <Suspense fallback={<div className="parcel-world-loading" aria-hidden="true" />}><ParcelWorld progress={progressRef} reducedMotion={reducedMotion} /></Suspense>
        <div className="cinematic-grain" aria-hidden="true" />
        <div className="cinematic-hud" aria-hidden="true"><span>SKIPPY / MAC UTILITY</span><span>LOCAL-FIRST SYSTEM</span><span>SCENE {cinematicScenes[scene].number}</span></div>
        <div className="cinematic-scenes">
          {cinematicScenes.map((item, index) => <article className={`cinematic-copy ${index === scene ? 'active' : ''} cinematic-copy-${index}`} aria-hidden={index !== scene} key={item.label}><div className="cinematic-kicker"><span>{item.number}</span>{item.label}</div><h1>{item.title}</h1><p>{item.body}</p>{index === 0 && <div className="cinematic-actions"><button className="button cinematic-primary" type="button" onClick={onWaitlist}>Join waitlist <ChevronRight size={16} /></button><a href="#try">Skip to the live workspace <ArrowDown size={15} /></a></div>}</article>)}
        </div>
        <div className="cinematic-progress" aria-label="Skippy journey scenes">{cinematicScenes.map((item, index) => <button type="button" className={index === scene ? 'active' : ''} onClick={() => jumpToScene(index)} key={item.label}><span>{item.number}</span><i /><strong>{item.label}</strong></button>)}</div>
        <button className={`auto-tour ${autoTour ? 'active' : ''}`} type="button" onClick={() => setAutoTour(value => !value)} disabled={reducedMotion}><Play size={13} /> {autoTour ? 'Touring' : 'Auto tour'}</button>
        <div className="scroll-cue"><span>Scroll to move the parcel</span><i /></div>
      </div>
    </div>
  </section>
}

function InteractiveDemo() {
  const [files, setFiles] = useState(initialFiles)
  const [clips, setClips] = useState(initialClips)
  const [view, setView] = useState<ViewMode>('grid')
  const [panel, setPanel] = useState<Panel>(null)
  const [dragged, setDragged] = useState<number | null>(null)
  const [hotTarget, setHotTarget] = useState<string | null>(null)
  const [status, setStatus] = useState('Ready. Drop files, paste content, or use the keyboard.')
  const [query, setQuery] = useState('')
  const [url, setUrl] = useState('https://example.com/a-very-long-project-link')
  const [shortening, setShortening] = useState(false)
  const [newParcel, setNewParcel] = useState(false)
  const [parcelName, setParcelName] = useState('Launch handoff')
  const searchRef = useRef<HTMLInputElement>(null)

  const shownFiles = useMemo(() => files.filter(file => file.name.toLowerCase().includes(query.toLowerCase())), [files, query])
  const cycleView = () => setView(current => current === 'grid' ? 'list' : current === 'list' ? 'dial' : 'grid')
  const nextId = () => Date.now() + Math.round(Math.random() * 1000)

  const openPanel = (next: Panel) => setPanel(current => current === next ? null : next)
  const addClipboardItem = (clip: Omit<Clip, 'id'>) => setClips(current => [{ id: nextId(), ...clip }, ...current])

  const removeDragged = () => {
    if (dragged === null) return
    const file = files.find(item => item.id === dragged)
    setFiles(current => current.filter(item => item.id !== dragged))
    setStatus(`${file?.name ?? 'Item'} moved to Bin.`)
  }

  const copyDraggedToClipboard = () => {
    const file = files.find(item => item.id === dragged)
    if (!file) return
    addClipboardItem({ title: file.name, detail: `${file.size} · file`, kind: 'file' })
    setPanel('clipboard')
    setStatus(`${file.name} added to Clipboard.`)
  }

  const finishDrop = (action: 'delete' | 'clipboard' | 'parcel') => {
    if (action === 'delete') removeDragged()
    if (action === 'clipboard') copyDraggedToClipboard()
    if (action === 'parcel') setNewParcel(true)
    setDragged(null)
    setHotTarget(null)
  }

  const captureExternalFiles = (event: DragEvent<HTMLDivElement>) => {
    if (dragged !== null || event.dataTransfer.files.length === 0) return
    event.preventDefault()
    const additions = Array.from(event.dataTransfer.files).map((file, index) => ({
      id: nextId() + index,
      name: file.name,
      kind: file.type.startsWith('image/') ? 'image' as const : file.type.startsWith('video/') ? 'video' as const : 'document' as const,
      size: file.size > 1_000_000 ? `${(file.size / 1_000_000).toFixed(1)} MB` : `${Math.max(1, Math.round(file.size / 1000))} KB`,
    }))
    setFiles(current => [...current, ...additions])
    setStatus(`${additions.length} ${additions.length === 1 ? 'file' : 'files'} parked in Skippy. Nothing was uploaded.`)
  }

  const capturePaste = async () => {
    try {
      const text = await navigator.clipboard.readText()
      if (!text) throw new Error('No readable text')
      addClipboardItem({ title: 'Pasted text', detail: text, kind: text.startsWith('http') ? 'link' : 'text' })
      setPanel('clipboard')
      setStatus('Clipboard text captured.')
    } catch {
      setStatus('Browser clipboard permission was not granted. Press ⌘V while the demo is focused instead.')
    }
  }

  const shorten = async () => {
    let valid: URL
    try { valid = new URL(url) } catch { setStatus('Enter a full http or https URL.'); return }
    if (!['http:', 'https:'].includes(valid.protocol)) { setStatus('Only http and https links can be shortened.'); return }
    setShortening(true)
    setStatus('Shortening link…')
    try {
      const response = await fetch(`/api/shorten?url=${encodeURIComponent(valid.href)}`)
      if (!response.ok) throw new Error('Shortener unavailable')
      const short = (await response.text()).trim()
      addClipboardItem({ title: 'Shortened link', detail: short, kind: 'link' })
      await navigator.clipboard.writeText(short).catch(() => undefined)
      setStatus('Short link copied and added to Clipboard.')
    } catch {
      setStatus('The live shortening service is unavailable right now. Your original link was not changed.')
    } finally { setShortening(false) }
  }

  const handleKeyboard = (event: KeyboardEvent<HTMLDivElement>) => {
    if ((event.target as HTMLElement).matches('input, button')) return
    if (event.key === '/') { event.preventDefault(); setPanel('search'); requestAnimationFrame(() => searchRef.current?.focus()) }
    if (event.key === '?' && event.shiftKey) { event.preventDefault(); setPanel('search'); setStatus('Filters opened: try “pdf”, “image”, or part of a filename.') }
    if (event.metaKey && event.key.toLowerCase() === 'p') { event.preventDefault(); setStatus(`Packed ${files.length} items into Launch handoff.zip.`) }
    if (event.metaKey && event.key.toLowerCase() === 'c') { event.preventDefault(); setStatus(`Copied ${files.length} items from the current parcel.`) }
  }

  const ViewIcon = view === 'grid' ? Grid2X2 : view === 'list' ? List : Layers3

  return (
    <section className="demo-section" id="try" aria-labelledby="demo-title">
      <div className="section-heading">
        <div><div className="eyebrow"><span /> Not a mockup</div><h2 id="demo-title">Try the flow before you download it.</h2></div>
        <p>Drop local files, paste text, switch views, search and shorten a real link. Use the controls, drag and drop, or try a shortcut—whatever feels natural.</p>
      </div>
      <div className="demo-desktop" onDragOver={event => event.preventDefault()} onDrop={captureExternalFiles} onKeyDown={handleKeyboard} onPaste={event => {
        const text = event.clipboardData.getData('text/plain')
        if (!text) return
        addClipboardItem({ title: 'Pasted text', detail: text, kind: text.startsWith('http') ? 'link' : 'text' })
        setPanel('clipboard'); setStatus('Pasted content captured as text.')
      }} tabIndex={0} aria-label="Interactive Skippy product demo">
        <div className="mac-menu" aria-hidden="true"><span>● ● ●</span><span>Thu 9:41</span></div>
        <div className="wallpaper-glow one" /><div className="wallpaper-glow two" />
        <div className="parcel-island">
          <div className="island-toolbar">
            <div className="toolbar-start">
              <MagneticButton label="New parcel" icon={PackagePlus} hot={hotTarget === 'parcel'} onClick={() => setNewParcel(true)} onDragEnter={() => setHotTarget('parcel')} onDragLeave={() => setHotTarget(null)} onDrop={() => finishDrop('parcel')} />
              <MagneticButton label="Clipboard" icon={Clipboard} hot={hotTarget === 'clipboard'} active={panel === 'clipboard'} onClick={() => openPanel('clipboard')} onDragEnter={() => setHotTarget('clipboard')} onDragLeave={() => setHotTarget(null)} onDrop={() => finishDrop('clipboard')} />
              <MagneticButton label="Other parcels" icon={Layers3} active={panel === 'parcels'} onClick={() => openPanel('parcels')} />
            </div>
            <strong>Launch handoff</strong>
            <div className="toolbar-end">
              <button className="tool-button" type="button" onClick={cycleView} aria-label={`Change view. Current view: ${view}`} title={`View: ${view}`}><ViewIcon size={16} /></button>
              <button className="tool-button" type="button" onClick={() => openPanel('search')} aria-label="Search parcel" title="Search (/)"><Search size={16} /></button>
              <MagneticButton label="Delete item" icon={Trash2} hot={hotTarget === 'delete'} onClick={() => setStatus('Drag an item here to move it to Bin.')} onDragEnter={() => setHotTarget('delete')} onDragLeave={() => setHotTarget(null)} onDrop={() => finishDrop('delete')} />
            </div>
          </div>
          <div className={`file-stage view-${view}`}>
            {shownFiles.map((file, index) => <FileCard key={file.id} file={file} index={index} view={view} onDragStart={() => { setDragged(file.id); setStatus(`Moving ${file.name}. Bring it near an action.`) }} onDragEnd={() => { setDragged(null); setHotTarget(null) }} />)}
            {shownFiles.length === 0 && <div className="empty-state">No matches. Clear search to bring every item back.</div>}
          </div>
          <div className="island-status" aria-live="polite"><span className="status-dot" /> {status}<button type="button" onClick={capturePaste}>Paste</button></div>
        </div>

        {panel === 'clipboard' && <ClipboardPanel clips={clips} url={url} setUrl={setUrl} shorten={shorten} shortening={shortening} close={() => setPanel(null)} setStatus={setStatus} />}
        {panel === 'parcels' && <SidePanel title="Parcels" close={() => setPanel(null)}><button className="parcel-choice" type="button"><img src="/media/parcel-icon.png" alt="" /><span><strong>Launch handoff</strong><small>Pinned · {files.length} items</small></span></button><button className="parcel-choice" type="button"><img src="/media/parcel-icon.png" alt="" /><span><strong>Reference</strong><small>Recent · 8 items</small></span></button></SidePanel>}
        {panel === 'search' && <SearchPanel query={query} setQuery={setQuery} files={shownFiles} close={() => setPanel(null)} inputRef={searchRef} />}

        {newParcel && <div className="dialog-backdrop" role="presentation"><form className="demo-dialog" onSubmit={event => { event.preventDefault(); setNewParcel(false); setStatus(`Created and pinned “${parcelName || 'Untitled parcel'}”.`) }}><div className="dialog-icon"><PackagePlus size={20} /></div><h3>Name your new parcel</h3><p>It becomes the pinned destination for the next thing you drop.</p><label>Parcel name<input autoFocus value={parcelName} onChange={event => setParcelName(event.target.value)} /></label><div><button className="button button-quiet" type="button" onClick={() => setNewParcel(false)}>Cancel</button><button className="button button-primary" type="submit">Create & pin</button></div></form></div>}
      </div>
      <p className="demo-footnote"><ShieldCheck size={14} /> The sandbox reads only filenames, sizes and content you explicitly paste. It does not upload dropped files.</p>
    </section>
  )
}

function MagneticButton({ label, icon: Icon, hot = false, active = false, onClick, onDragEnter, onDragLeave, onDrop }: { label: string; icon: typeof Clipboard; hot?: boolean; active?: boolean; onClick: () => void; onDragEnter?: () => void; onDragLeave?: () => void; onDrop?: () => void }) {
  return <button className={`tool-button magnetic ${hot ? 'is-hot' : ''} ${active ? 'is-active' : ''}`} type="button" onClick={onClick} title={label} aria-label={label} onDragOver={event => event.preventDefault()} onDragEnter={onDragEnter} onDragLeave={onDragLeave} onDrop={event => { event.preventDefault(); event.stopPropagation(); onDrop?.() }}><Icon size={17} /><span>{label}</span></button>
}

function FileCard({ file, view, index, onDragStart, onDragEnd }: { file: ParcelFile; view: ViewMode; index: number; onDragStart: () => void; onDragEnd: () => void }) {
  const Icon = kindIcons[file.kind]
  return <button className="file-card" style={{ '--item-index': index } as React.CSSProperties} type="button" draggable onDragStart={onDragStart} onDragEnd={onDragEnd} title={`${file.name} · ${file.size}`}><span className={`file-icon kind-${file.kind}`}><Icon size={view === 'list' ? 18 : 24} /></span><span className="file-name">{file.name}</span><small>{file.size}</small></button>
}

function SidePanel({ title, close, children }: { title: string; close: () => void; children: React.ReactNode }) {
  return <aside className="side-panel" aria-label={title}><div className="panel-head"><strong>{title}</strong><button onClick={close} type="button" aria-label={`Close ${title}`}>×</button></div>{children}</aside>
}

function ClipboardPanel({ clips, url, setUrl, shorten, shortening, close, setStatus }: { clips: Clip[]; url: string; setUrl: (value: string) => void; shorten: () => void; shortening: boolean; close: () => void; setStatus: (value: string) => void }) {
  const [filter, setFilter] = useState('')
  const shown = clips.filter(clip => `${clip.title} ${clip.detail}`.toLowerCase().includes(filter.toLowerCase()))
  return <SidePanel title="Clipboard" close={close}>
    <div className="panel-search"><Search size={14} /><input aria-label="Search clipboard" placeholder="Search clipboard…" value={filter} onChange={event => setFilter(event.target.value)} /></div>
    <div className="shortener"><label htmlFor="shorten-url">Shorten a link</label><div><input id="shorten-url" value={url} onChange={event => setUrl(event.target.value)} /><button type="button" onClick={shorten} disabled={shortening}>{shortening ? '…' : 'Shorten'}</button></div></div>
    <div className="clip-list">{shown.map(clip => <article className="clip-row" key={clip.id} draggable><span className={`clip-kind ${clip.kind}`}><Clipboard size={14} /></span><span><strong>{clip.title}</strong><small>{clip.detail}</small></span><button type="button" aria-label={`Copy ${clip.title}`} onClick={async () => { await navigator.clipboard.writeText(clip.detail).catch(() => undefined); setStatus(`${clip.title} copied.`) }}><Copy size={14} /></button></article>)}</div>
  </SidePanel>
}

function SearchPanel({ query, setQuery, files, close, inputRef }: { query: string; setQuery: (value: string) => void; files: ParcelFile[]; close: () => void; inputRef: React.RefObject<HTMLInputElement | null> }) {
  return <SidePanel title="Search" close={close}><div className="panel-search large"><Search size={15} /><input ref={inputRef} placeholder="Try “metrics” or “png”" value={query} onChange={event => setQuery(event.target.value)} /><button type="button" title="Filters"><Filter size={15} /></button></div><div className="filter-chips"><button type="button" onClick={() => setQuery('pdf')}>Documents</button><button type="button" onClick={() => setQuery('png')}>Images</button><button type="button" onClick={() => setQuery('mov')}>Video</button></div><div className="search-results">{files.map(file => <div key={file.id}><span>{file.name}</span><small>{file.size}</small></div>)}</div></SidePanel>
}

function Proof() {
  return <section className="proof-section" id="proof"><div className="section-heading"><div><div className="eyebrow"><span /> Clean demo workspace</div><h2>Real interactions. Nothing personal on screen.</h2></div><p>These recordings exercise the working browser sandbox inside an isolated Skippy workspace—no desktop, notifications, accounts or private files visible.</p></div><div className="video-grid"><VideoCard src="/media/parcel-link-demo.webm" poster="/media/parcel-link-demo.png" kicker="Clipboard" title="Shorten and recapture links" /><VideoCard src="/media/parcel-magnetic-demo.webm" poster="/media/parcel-magnetic-demo.png" kicker="Drag & drop" title="Targets meet your cursor halfway" /></div></section>
}

function VideoCard({ src, poster, kicker, title }: { src: string; poster: string; kicker: string; title: string }) {
  return <figure className="video-card"><video controls muted playsInline preload="metadata" poster={poster}><source src={src} type="video/webm" />Your browser cannot play this recording.</video><figcaption><span>{kicker}</span><strong>{title}</strong></figcaption></figure>
}

function FeatureGrid() {
  return <section className="features-section" id="features"><div className="section-heading"><div><div className="eyebrow"><span /> One habit, fewer interruptions</div><h2>Inside your quiver.</h2></div><p>Pin your everyday arrows, then open them directly from the menu bar, notch or screen edge.</p></div><div className="feature-grid">{features.map(({ icon: Icon, tag, title, body }) => <SpotlightCard key={title} className="feature-card" theme="light" spotlightColor="#735a39" intensity={0.18} spotlightSize={210} borderGlow={0.4}><div className="feature-icon"><Icon size={21} /></div><span className="feature-tag">{tag}</span><h3>{title}</h3><p>{body}</p></SpotlightCard>)}</div></section>
}

function WaysToWorkSection() {
  return <section className="keyboard-section" id="shortcuts"><div className="keyboard-copy"><div className="eyebrow light"><span /> Use Skippy your way</div><h2>Obvious with a mouse. Faster when you want it.</h2><p>Drag files into the shelf, click clear controls, paste anything, use Finder actions, or learn shortcuts over time. Skippy never expects you to change how you use your Mac.</p><a href="#try" className="text-link">Try the live shelf <ChevronRight size={15} /></a></div><div className="shortcut-board" role="list" aria-label="Optional Skippy keyboard shortcuts">{shortcuts.map(([keys, action]) => <div className="shortcut-row" role="listitem" key={keys}><kbd>{keys}</kbd><span>{action}</span></div>)}</div></section>
}

function AccessibilitySection() {
  return <section className="access-section"><div className="access-card"><div className="access-icon"><Accessibility size={28} /></div><div><div className="eyebrow"><span /> Designed for more ways of working</div><h2>Fast should never mean fragile.</h2><p>Clear focus states, full keyboard paths, large hit targets, semantic controls, high-contrast fallbacks and reduced-motion behavior are part of the product—not a polish pass at the end.</p></div><ul><li><Check size={16} /> Reduced Motion respected</li><li><Check size={16} /> Reduce Transparency fallback</li><li><Check size={16} /> VoiceOver-friendly labels</li><li><Check size={16} /> Keyboard-operable workflows</li></ul></div></section>
}

function FinalCta({ onWaitlist }: { onWaitlist: () => void }) {
  return <section className="final-cta"><div className="cta-spark one" /><div className="cta-spark two" /><img src="/media/parcel-icon.png" alt="Skippy app icon" /><div><div className="eyebrow light"><span /> A tiny app you will use all day</div><h2>Keep the thought.<br />Move the thing.</h2><p>Skippy starts at $2.49 for one Mac. Join the waitlist for launch access—one purchase, no subscription.</p><button className="button button-light" type="button" onClick={onWaitlist}>Join the waitlist <ChevronRight size={16} /></button></div></section>
}

function Footer() {
  return <footer><a className="brand" href="/#top"><img src="/media/parcel-icon.png" alt="" /><span>Skippy</span></a><p>Built for Mac workflows. Private, local-first and subscription-free.</p><div><a href="/#try">Live demo</a><a href="/#features">Features</a><a href="/pricing">Pricing</a></div></footer>
}

function PricingPage() {
  const [waitlistOpen, setWaitlistOpen] = useState(false)
  const [selectedPlan, setSelectedPlan] = useState('two')
  const plans = [
    { id: 'single', name: 'Single Mac', price: '$2.49', note: 'one-time licence', icon: Monitor, featured: false, items: ['Use on 1 Mac', 'Every Skippy feature', 'Local conversion and OCR', 'No subscription'] },
    { id: 'two', name: 'Two Macs', price: '$4.99', note: 'one-time licence', icon: Monitor, featured: true, items: ['Use on 2 Macs', 'Every Skippy feature', 'Clipboard and link tools', 'Version 1.x updates'] },
    { id: 'five', name: 'Five Macs', price: '$9.99', note: 'one-time licence', icon: Users, featured: false, items: ['Use on 5 Macs', 'Every Skippy feature', 'One licence to manage', 'No subscription'] },
  ]

  return <div className="pricing-page">
    <header className="topbar pricing-nav"><a className="brand" href="/" aria-label="Skippy home"><img src="/media/parcel-icon.png" alt="" /><span>Skippy</span></a><nav aria-label="Pricing navigation"><a href="/#top">The journey</a><a href="/#features">Features</a><a href="/pricing" aria-current="page">Pricing</a></nav><a className="button button-small" href="/"><ArrowLeft size={15} /> Back to demo</a></header>
    <main className="pricing-main">
      <section className="pricing-hero"><div className="eyebrow"><span /> One small purchase for a calmer Mac</div><h1>Pay once.<br /><em>Use it every day.</em></h1><p>Every plan includes the complete Skippy experience. Choose only how many Macs you want to activate.</p><div className="pricing-pills"><span><Check size={14} /> All features included</span><span><Check size={14} /> No subscription</span><span><Check size={14} /> Local-first processing</span></div></section>
      <section className="pricing-grid" aria-label="Skippy pricing plans">{plans.map(({ id, name, price, note, icon: Icon, featured, items }) => <article className={`price-card ${featured ? 'featured' : ''}`} key={name}>{featured && <div className="popular">Best for most people</div>}<div className="price-icon"><Icon size={22} /></div><h2>{name}</h2><div className="price"><strong>{price}</strong><span>USD</span></div><p>{note}</p><ul>{items.map(item => <li key={item}><Check size={15} /> {item}</li>)}</ul><button type="button" onClick={() => { setSelectedPlan(id); setWaitlistOpen(true) }}>Join waitlist</button></article>)}</section>
      <section className="pricing-note"><ShieldCheck size={24} /><div><h2>No payment is collected yet.</h2><p>Join the launch waitlist for your chosen Mac licence. Skippy requires a valid signed licence before its shelf, clipboard or file tools become available.</p></div><button type="button" onClick={() => setWaitlistOpen(true)}>Join waitlist <ChevronRight size={15} /></button></section>
      <section className="pricing-faq"><div><div className="eyebrow"><span /> Practical answers</div><h2>Before you choose.</h2></div><div className="faq-list"><details open><summary>Does every plan include every feature?</summary><p>Yes. Plans differ only by the number of Macs you can activate.</p></details><details><summary>Is Skippy a subscription?</summary><p>No. These are one-time prices for Skippy version 1.x.</p></details><details><summary>Does Skippy work without a licence?</summary><p>No. Production builds open the activation screen first and unlock the app only after a signed licence is verified on your Mac.</p></details><details><summary>Where are converted files stored?</summary><p>Results stay in Skippy-owned local storage and are added back to your parcel. Originals are not modified.</p></details></div></section>
    </main>
    <Footer />
    {waitlistOpen && <WaitlistDialog close={() => setWaitlistOpen(false)} initialPlan={selectedPlan} />}
  </div>
}

function WaitlistDialog({ close, initialPlan = 'two' }: { close: () => void; initialPlan?: string }) {
  const [state, setState] = useState<'idle' | 'sending' | 'success' | 'error'>('idle')
  const [message, setMessage] = useState('')
  const dialogRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    dialogRef.current?.querySelector<HTMLInputElement>('input[name="email"]')?.focus()
    const onKey = (event: globalThis.KeyboardEvent) => { if (event.key === 'Escape') close() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [close])
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setState('sending'); setMessage('')
    const data = new FormData(event.currentTarget)
    try {
      const response = await fetch('/api/waitlist', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(Object.fromEntries(data)) })
      const result = await response.json().catch(() => ({ message: 'The waitlist is being connected. Please try again shortly.' })) as { message?: string }
      if (!response.ok) throw new Error(result.message || 'Could not join the waitlist.')
      setState('success')
    } catch (error) {
      setState('error'); setMessage(error instanceof Error ? error.message : 'Could not join the waitlist.')
    }
  }
  return <div className="waitlist-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) close() }}><div className="waitlist-dialog" ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby="waitlist-title"><button className="waitlist-close" type="button" onClick={close} aria-label="Close waitlist">×</button>{state === 'success' ? <div className="waitlist-success"><span><Check size={24} /></span><h2 id="waitlist-title">You are on the list.</h2><p>Check your inbox for confirmation. We will let you know when Skippy is ready for your Mac.</p><button className="button button-primary" type="button" onClick={close}>Done</button></div> : <><div className="eyebrow"><span /> Early access</div><h2 id="waitlist-title">Make your Mac feel easier.</h2><p>Choose your licence and we will email you when Skippy is ready. No payment today.</p><form onSubmit={submit}><label>Name <input name="name" autoComplete="name" maxLength={80} placeholder="Your name" /></label><label>Email <input name="email" type="email" autoComplete="email" required maxLength={254} placeholder="you@example.com" /></label><label>Mac licence <select name="plan" defaultValue={initialPlan}><option value="single">1 Mac · $2.49</option><option value="two">2 Macs · $4.99</option><option value="five">5 Macs · $9.99</option></select></label><label className="honeypot" aria-hidden="true">Company website <input name="website" tabIndex={-1} autoComplete="off" /></label><label className="consent"><input name="consent" type="checkbox" value="yes" required /> Email me about Skippy's launch. I can unsubscribe at any time.</label>{state === 'error' && <p className="form-error" role="alert">{message}</p>}<button className="button button-primary" type="submit" disabled={state === 'sending'}>{state === 'sending' ? 'Joining…' : 'Join waitlist'} <ChevronRight size={15} /></button></form></>}</div></div>
}

export default App
