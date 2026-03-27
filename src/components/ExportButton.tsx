import { Download } from 'lucide-react'
import type { Plant } from '../lib/api'
import { stageLabel } from '../lib/stages'

function plantsToCsv(plants: Plant[]): string {
  const headers = ['Variety', 'Crop Type', 'Stage', 'Bed ID', 'Sow Date', 'Germination Date', 'Transplant Date', 'Quantity']
  const rows = plants.map(p => [
    p.variety_name,
    p.crop_type,
    stageLabel(p.lifecycle_stage),
    p.bed_id || '',
    p.sow_date || '',
    p.germination_date || '',
    p.transplant_date || '',
    p.quantity || 1,
  ])
  return [headers, ...rows].map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n')
}

export function ExportButton({ plants }: { plants: Plant[] }) {
  const handleExport = () => {
    const csv = plantsToCsv(plants)
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `garden-plants-${new Date().toISOString().split('T')[0]}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <button
      onClick={handleExport}
      className="btn-ghost text-xs py-2 flex items-center gap-1.5"
      title="Export plants as CSV"
    >
      <Download size={14} />
      Export
    </button>
  )
}
