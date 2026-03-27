import { useRef, useEffect, useState, useCallback } from 'react'
import { Html5Qrcode } from 'html5-qrcode'
import { Camera, X, Loader2 } from 'lucide-react'
import { toast } from '../lib/toast'

interface BarcodeScannerProps {
  onScan: (barcode: string) => void
  onClose: () => void
}

export function BarcodeScanner({ onScan, onClose }: BarcodeScannerProps) {
  const scannerRef = useRef<Html5Qrcode | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const scanner = new Html5Qrcode('barcode-reader')
    scannerRef.current = scanner

    scanner.start(
      { facingMode: 'environment' },
      { fps: 10, qrbox: { width: 250, height: 100 } },
      (decodedText) => {
        scanner.stop().catch(() => {})
        onScan(decodedText)
      },
      () => {} // ignore scan failures
    ).catch((err) => {
      setError('Camera access denied. Please allow camera access to scan barcodes.')
      console.error('Scanner error:', err)
    })

    return () => {
      scanner.stop().catch(() => {})
    }
  }, [onScan])

  return (
    <div className="fixed inset-0 z-50 bg-black flex flex-col">
      <div className="flex items-center justify-between p-4">
        <h3 className="text-white font-medium text-sm">Scan seed packet barcode</h3>
        <button onClick={onClose} className="p-2 text-white/80 hover:text-white min-h-[44px] min-w-[44px] flex items-center justify-center">
          <X size={20} />
        </button>
      </div>
      <div className="flex-1 flex items-center justify-center">
        {error ? (
          <div className="text-center px-8">
            <p className="text-white/80 text-sm">{error}</p>
            <button onClick={onClose} className="mt-4 btn-primary">Go back</button>
          </div>
        ) : (
          <div id="barcode-reader" className="w-full max-w-sm" />
        )}
      </div>
      <p className="text-white/50 text-xs text-center pb-8 px-4">
        Point camera at the EAN barcode on the seed packet
      </p>
    </div>
  )
}

// Scan button for the seeds page
export function ScanButton({ onScan }: { onScan: (barcode: string) => void }) {
  const [scanning, setScanning] = useState(false)
  const [looking, setLooking] = useState(false)

  const handleScan = useCallback(async (barcode: string) => {
    setScanning(false)
    setLooking(true)

    try {
      // Look up via our backend (tries Open Food Facts, UPC Item DB, OpenGTINdb)
      const res = await fetch(`/api/seeds/ean/${barcode}`)
      const data = await res.json()

      if (data.found && data.name) {
        const label = data.brand ? `${data.name} (${data.brand})` : data.name
        onScan(label)
        toast.success(`Found: ${label}`)
      } else {
        onScan(barcode)
        toast.info(`EAN ${barcode} not found — enter seed details manually`)
      }
    } catch {
      onScan(barcode)
      toast.info(`Scanned: ${barcode}`)
    } finally {
      setLooking(false)
    }
  }, [onScan])

  return (
    <>
      <button
        onClick={() => setScanning(true)}
        disabled={looking}
        className="btn-secondary text-sm flex items-center gap-2"
        title="Scan seed packet barcode"
      >
        {looking ? <Loader2 size={16} className="animate-spin" /> : <Camera size={16} />}
        {looking ? 'Looking up...' : 'Scan'}
      </button>
      {scanning && <BarcodeScanner onScan={handleScan} onClose={() => setScanning(false)} />}
    </>
  )
}
