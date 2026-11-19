import { useEffect, useRef, type RefObject } from 'react'
import * as THREE from 'three'
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js'

type ParcelWorldProps = {
  progress: RefObject<number>
  reducedMotion: boolean
}

const clamp = (value: number) => Math.max(0, Math.min(1, value))
const ease = (value: number) => {
  const t = clamp(value)
  return t * t * (3 - 2 * t)
}
const mix = (from: number, to: number, amount: number) => from + (to - from) * amount

function labelTexture(label: string, tint: string) {
  const canvas = document.createElement('canvas')
  canvas.width = 256
  canvas.height = 320
  const context = canvas.getContext('2d')!
  context.fillStyle = '#f6f3e9'
  context.fillRect(0, 0, canvas.width, canvas.height)
  context.fillStyle = tint
  context.fillRect(0, 0, canvas.width, 18)
  context.fillRect(24, 48, 68, 68)
  context.fillStyle = '#252820'
  context.font = '700 25px Arial'
  context.fillText(label, 24, 160)
  context.fillStyle = '#8c8a7f'
  context.font = '16px Arial'
  context.fillText('READY TO MOVE', 24, 198)
  context.fillRect(24, 232, 180, 8)
  context.fillRect(24, 252, 138, 8)
  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace
  texture.anisotropy = 4
  return texture
}

function parcelLabelTexture() {
  const canvas = document.createElement('canvas')
  canvas.width = 512
  canvas.height = 160
  const context = canvas.getContext('2d')!
  context.fillStyle = '#294b39'
  context.beginPath()
  context.moveTo(44, 10)
  context.lineTo(468, 10)
  context.quadraticCurveTo(502, 10, 502, 44)
  context.lineTo(502, 116)
  context.quadraticCurveTo(502, 150, 468, 150)
  context.lineTo(44, 150)
  context.quadraticCurveTo(10, 150, 10, 116)
  context.lineTo(10, 44)
  context.quadraticCurveTo(10, 10, 44, 10)
  context.fill()
  context.fillStyle = '#f4e3be'
  context.font = '700 72px Arial'
  context.textAlign = 'center'
  context.textBaseline = 'middle'
  context.fillText('parcel', 256, 84)
  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace
  return texture
}

export default function ParcelWorld({ progress, reducedMotion }: ParcelWorldProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    let renderer: THREE.WebGLRenderer
    try {
      renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' })
    } catch {
      canvas.dataset.failed = 'true'
      return
    }

    const scene = new THREE.Scene()
    scene.fog = new THREE.FogExp2(0x171a17, 0.075)
    const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 100)
    camera.position.set(0, 0.4, 8)
    renderer.setClearColor(0x171a17, 0)
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, window.innerWidth < 700 ? 1 : 1.35))
    renderer.outputColorSpace = THREE.SRGBColorSpace
    renderer.toneMapping = THREE.ACESFilmicToneMapping
    renderer.toneMappingExposure = 1.12

    scene.add(new THREE.HemisphereLight(0xf2e8d2, 0x233129, 2.3))
    const key = new THREE.DirectionalLight(0xffd69b, 5.2)
    key.position.set(-3, 5, 5)
    scene.add(key)
    const rim = new THREE.PointLight(0x82d79c, 30, 18)
    rim.position.set(4, -1, 2)
    scene.add(rim)

    const world = new THREE.Group()
    scene.add(world)

    const parcel = new THREE.Group()
    world.add(parcel)
    const kraft = new THREE.MeshStandardMaterial({ color: 0xc89254, roughness: 0.56, metalness: 0.06 })
    const edge = new THREE.MeshStandardMaterial({ color: 0x5a3c23, roughness: 0.7 })
    const ribbon = new THREE.MeshStandardMaterial({ color: 0x294b39, roughness: 0.42, metalness: 0.08 })
    const base = new THREE.Mesh(new RoundedBoxGeometry(2.55, 1.25, 1.65, 5, 0.1), kraft)
    base.position.y = -0.2
    parcel.add(base)
    const lidPivot = new THREE.Group()
    lidPivot.position.set(0, 0.48, -0.75)
    parcel.add(lidPivot)
    const lid = new THREE.Mesh(new RoundedBoxGeometry(2.65, 0.35, 1.75, 5, 0.1), kraft)
    lid.position.set(0, 0, 0.75)
    lidPivot.add(lid)
    const bandX = new THREE.Mesh(new THREE.BoxGeometry(2.7, 0.13, 0.22), ribbon)
    bandX.position.set(0, 0.34, 0.7)
    parcel.add(bandX)
    const bandZ = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.13, 1.72), ribbon)
    bandZ.position.set(0, 0.34, 0)
    parcel.add(bandZ)
    const parcelShadow = new THREE.Mesh(new THREE.CircleGeometry(2, 64), new THREE.MeshBasicMaterial({ color: 0x050705, transparent: true, opacity: 0.38, depthWrite: false }))
    parcelShadow.rotation.x = -Math.PI / 2
    parcelShadow.position.y = -0.92
    parcelShadow.scale.y = 0.42
    parcel.add(parcelShadow)
    const frontLabelMaterial = new THREE.MeshBasicMaterial({ map: parcelLabelTexture(), transparent: true, depthWrite: false })
    const frontLabel = new THREE.Mesh(new THREE.PlaneGeometry(1.16, 0.36), frontLabelMaterial)
    frontLabel.position.set(0, -0.28, 0.834)
    parcel.add(frontLabel)
    for (let index = 0; index < 13; index += 1) {
      const tooth = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.08, 0.13), edge)
      tooth.position.set(-1.05 + index * 0.175, 0.57, 0.91)
      parcel.add(tooth)
    }

    const labels = [
      ['PDF', '#d9634e'], ['PNG', '#c7955e'], ['XLS', '#3f8f5b'], ['MOV', '#8266a8'],
      ['LINK', '#4c7ca2'], ['TXT', '#79766e'], ['DOC', '#5578bb'], ['OCR', '#6f8f67'],
    ]
    const fileGeometry = new THREE.PlaneGeometry(0.86, 1.08)
    const files = labels.map(([label, tint], index) => {
      const material = new THREE.MeshStandardMaterial({ map: labelTexture(label, tint), roughness: 0.46, metalness: 0.02, side: THREE.DoubleSide, transparent: true })
      const mesh = new THREE.Mesh(fileGeometry, material)
      mesh.userData.angle = (index / labels.length) * Math.PI * 2
      mesh.userData.depth = index % 2 ? -0.35 : 0.32
      world.add(mesh)
      return mesh
    })

    const ringMaterial = new THREE.LineBasicMaterial({ color: 0xe0bf88, transparent: true, opacity: 0.28 })
    const ringPoints = Array.from({ length: 96 }, (_, index) => {
      const angle = (index / 96) * Math.PI * 2
      return new THREE.Vector3(Math.cos(angle) * 2.8, Math.sin(angle) * 2.8, 0)
    })
    const ring = new THREE.LineLoop(new THREE.BufferGeometry().setFromPoints(ringPoints), ringMaterial)
    ring.rotation.x = 0.3
    world.add(ring)

    const portalMaterial = new THREE.MeshStandardMaterial({ color: 0x8bd19f, emissive: 0x376f4a, emissiveIntensity: 3.5, transparent: true, opacity: 0 })
    const portal = new THREE.Mesh(new THREE.TorusGeometry(1.4, 0.045, 12, 96), portalMaterial)
    portal.position.set(2.35, 0, -2.8)
    portal.rotation.y = -0.32
    scene.add(portal)
    const portalEcho = new THREE.Mesh(new THREE.TorusGeometry(1.75, 0.018, 8, 96), portalMaterial.clone())
    portalEcho.position.copy(portal.position)
    portalEcho.rotation.copy(portal.rotation)
    scene.add(portalEcho)

    const particleCount = window.innerWidth < 700 ? 100 : 220
    const particlePositions = new Float32Array(particleCount * 3)
    for (let index = 0; index < particleCount; index += 1) {
      particlePositions[index * 3] = (Math.random() - 0.5) * 18
      particlePositions[index * 3 + 1] = (Math.random() - 0.5) * 11
      particlePositions[index * 3 + 2] = (Math.random() - 0.5) * 12
    }
    const particleGeometry = new THREE.BufferGeometry()
    particleGeometry.setAttribute('position', new THREE.BufferAttribute(particlePositions, 3))
    const particles = new THREE.Points(particleGeometry, new THREE.PointsMaterial({ color: 0xe8d4ad, size: 0.025, transparent: true, opacity: 0.55 }))
    scene.add(particles)

    const pointer = new THREE.Vector2()
    const targetPointer = new THREE.Vector2()
    const handlePointer = (event: PointerEvent) => {
      targetPointer.set((event.clientX / window.innerWidth - 0.5) * 2, (event.clientY / window.innerHeight - 0.5) * 2)
    }
    window.addEventListener('pointermove', handlePointer, { passive: true })

    const resize = () => {
      const width = canvas.clientWidth || window.innerWidth
      const height = canvas.clientHeight || window.innerHeight
      renderer.setSize(width, height, false)
      camera.aspect = width / height
      camera.updateProjectionMatrix()
    }
    const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(resize)
    observer?.observe(canvas)
    window.addEventListener('resize', resize, { passive: true })
    resize()

    const startedAt = performance.now()
    let previousFrame = startedAt
    let smoothProgress = clamp(progress.current ?? 0)
    let inViewport = true
    let pageVisible = !document.hidden
    let contextAvailable = true
    let frame = 0
    const render = (now = performance.now()) => {
      if (!inViewport || !pageVisible || !contextAvailable) { frame = 0; return }
      const elapsed = (now - startedAt) / 1000
      const delta = Math.min(0.05, Math.max(0.001, (now - previousFrame) / 1000))
      previousFrame = now
      const targetProgress = reducedMotion ? 0.12 : clamp(progress.current ?? 0)
      smoothProgress += (targetProgress - smoothProgress) * (1 - Math.exp(-delta * 10))
      const value = smoothProgress
      const catchT = ease((value - 0.05) / 0.2)
      const prepareT = ease((value - 0.25) / 0.24)
      const packT = ease((value - 0.54) / 0.2)
      const sendT = ease((value - 0.77) / 0.2)
      const compact = window.innerWidth < 700
      const mobileScale = compact ? 0.58 : 1
      pointer.lerp(targetPointer, 1 - Math.exp(-delta * 7))

      files.forEach((file, index) => {
        const angle = file.userData.angle as number
        const startX = (index % 2 ? 1 : -1) * (4.7 + (index % 3) * 0.45)
        const startY = 2.35 - (index % 4) * 1.48
        const orbitX = Math.cos(angle + elapsed * 0.12) * 3.2
        const orbitY = Math.sin(angle + elapsed * 0.12) * 2.2
        const wheelX = Math.cos(angle + elapsed * 0.28) * 2.45
        const wheelY = Math.sin(angle + elapsed * 0.28) * 2.45
        const caughtX = mix(startX, orbitX, catchT)
        const caughtY = mix(startY, orbitY, catchT)
        const preparedX = mix(caughtX, wheelX, prepareT)
        const preparedY = mix(caughtY, wheelY, prepareT)
        file.position.set(mix(preparedX, 0, packT), mix(preparedY, 0.2, packT), mix(file.userData.depth as number, 0.05, packT))
        file.rotation.z = mix((index % 2 ? -1 : 1) * 0.13, angle + Math.PI / 2, prepareT) + pointer.x * 0.025
        file.rotation.y = pointer.x * 0.08
        const visibleScale = mix(1, 0.08, packT)
        file.scale.setScalar(visibleScale * (1 - sendT * 0.35) * (compact ? 0.72 : 1))
        ;(file.material as THREE.MeshStandardMaterial).opacity = 1 - packT
      })

      lidPivot.rotation.x = mix(-1.15, 0, packT)
      parcel.rotation.y = elapsed * 0.08 + value * Math.PI * 1.7 + pointer.x * 0.13
      parcel.rotation.x = -0.08 + pointer.y * 0.08
      parcel.position.y = Math.sin(elapsed * 0.8) * 0.08 + mix(0, 0.5, sendT)
      parcel.position.z = mix(0, -7, sendT)
      parcel.scale.setScalar(mix(1, 0.28, sendT) * mobileScale)
      ring.visible = prepareT > 0.05 && packT < 0.98
      ;(ring.material as THREE.LineBasicMaterial).opacity = prepareT * (1 - packT) * 0.42
      ring.rotation.z = elapsed * 0.18
      ring.scale.setScalar(mix(0.72, 1.14, prepareT) * mobileScale)
      portal.visible = sendT > 0.02
      portalEcho.visible = sendT > 0.02
      portalMaterial.opacity = sendT * 0.82
      ;(portalEcho.material as THREE.MeshStandardMaterial).opacity = sendT * 0.34
      portal.scale.setScalar(mix(0.55, 1, sendT) * mobileScale)
      portalEcho.scale.setScalar(mix(0.4, 1.08 + Math.sin(elapsed * 2.2) * 0.05, sendT) * mobileScale)
      portal.rotation.z = elapsed * 0.15
      portalEcho.rotation.z = -elapsed * 0.1
      world.rotation.z = mix(0, -0.12, sendT)
      world.position.x = mix(0, 2.4, sendT)

      camera.position.x = mix(0, -0.55, prepareT) + pointer.x * 0.12
      camera.position.y = mix(0.35, 0.12, packT) - pointer.y * 0.1
      camera.position.z = mix(8, 6.2, prepareT) + sendT * 1.5
      camera.lookAt(0, 0, 0)
      particles.rotation.y = elapsed * 0.018
      particles.position.z = (elapsed * 0.08) % 1
      renderer.render(scene, camera)
      frame = window.requestAnimationFrame(render)
    }

    const wake = () => {
      if (!frame && inViewport && pageVisible && contextAvailable) {
        previousFrame = performance.now()
        frame = window.requestAnimationFrame(render)
      }
    }
    const viewportObserver = typeof IntersectionObserver === 'undefined' ? null : new IntersectionObserver(([entry]) => {
      inViewport = entry.isIntersecting
      if (inViewport) wake()
    }, { rootMargin: '100px' })
    viewportObserver?.observe(canvas)
    const handleVisibility = () => { pageVisible = !document.hidden; if (pageVisible) wake() }
    const handleContextLost = (event: Event) => { event.preventDefault(); contextAvailable = false; canvas.dataset.failed = 'true' }
    const handleContextRestored = () => { contextAvailable = true; delete canvas.dataset.failed; wake() }
    document.addEventListener('visibilitychange', handleVisibility)
    canvas.addEventListener('webglcontextlost', handleContextLost)
    canvas.addEventListener('webglcontextrestored', handleContextRestored)
    wake()

    return () => {
      window.cancelAnimationFrame(frame)
      window.removeEventListener('pointermove', handlePointer)
      window.removeEventListener('resize', resize)
      document.removeEventListener('visibilitychange', handleVisibility)
      canvas.removeEventListener('webglcontextlost', handleContextLost)
      canvas.removeEventListener('webglcontextrestored', handleContextRestored)
      observer?.disconnect()
      viewportObserver?.disconnect()
      files.forEach(file => {
        ;(file.material as THREE.MeshStandardMaterial).map?.dispose()
        ;(file.material as THREE.MeshStandardMaterial).dispose()
      })
      fileGeometry.dispose()
      particleGeometry.dispose()
      frontLabelMaterial.map?.dispose()
      frontLabelMaterial.dispose()
      portalMaterial.dispose()
      ;(portalEcho.material as THREE.Material).dispose()
      renderer.dispose()
    }
  }, [progress, reducedMotion])

  return <canvas className="parcel-world" ref={canvasRef} aria-hidden="true" />
}
