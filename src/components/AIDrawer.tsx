import { useState, useRef, useEffect, useCallback } from 'react'
import { Sparkles, X, Send, Loader2, CheckCircle } from 'lucide-react'
import { renderMarkdown } from '../lib/markdown'
import { streamPlanner, type SSEEvent } from '../lib/api'
import { toast } from '../lib/toast'

interface Message {
  role: 'user' | 'assistant'
  content: string
}

interface DraftPlan {
  assignments?: Array<{ bed_name: string; variety_name: string; crop_type: string }>
  successions?: Array<{ crop_type: string; interval_days: number; total_sowings: number }>
  tasks?: Array<{ title: string; due_date: string }>
}

interface BedLayout {
  bed_name: string
  action: string
  suggestions?: Array<{ variety_name: string; crop_type: string; grid_x: number; grid_y: number; grid_w: number; grid_h: number }>
  moves?: Array<{ plant_id: number; grid_x: number; grid_y: number }>
}

interface AIDrawerProps {
  context?: Record<string, unknown>
  onClose: () => void
  open: boolean
  onDraftApplied?: () => void
}

function SafeMarkdown({ content }: { content: string }) {
  const html = renderMarkdown(content)
  return (
    <div
      className="prose prose-sm prose-green max-w-none [&_p]:my-1 [&_ul]:my-1 [&_li]:my-0 [&_h3]:text-sm [&_h3]:font-semibold [&_h3]:mt-2 [&_h3]:mb-1"
      dangerouslySetInnerHTML={{ __html: html }}
    />
  )
}

export function AIDrawer({ context, onClose, open, onDraftApplied }: AIDrawerProps) {
  const [messages, setMessages] = useState<Message[]>(() => {
    try {
      const saved = sessionStorage.getItem('ai_chat')
      return saved ? JSON.parse(saved) : []
    } catch { return [] }
  })
  const [input, setInput] = useState('')
  const [streaming, setStreaming] = useState(false)
  const [streamContent, setStreamContent] = useState('')
  const [draft, setDraft] = useState<DraftPlan | null>(null)
  const [bedLayout, setBedLayout] = useState<BedLayout | null>(null)
  const [committing, setCommitting] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const abortRef = useRef<(() => void) | null>(null)

  // Persist chat to sessionStorage
  useEffect(() => {
    try { sessionStorage.setItem('ai_chat', JSON.stringify(messages)) } catch {}
  }, [messages])

  useEffect(() => {
    if (open) setTimeout(() => inputRef.current?.focus(), 100)
  }, [open])

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, streamContent])

  const sendMessage = useCallback((overrideText?: string) => {
    const text = (overrideText || input).trim()
    if (!text || streaming) return

    if (!overrideText) setInput('')
    setMessages(prev => [...prev, { role: 'user', content: text }])
    setStreaming(true)
    setStreamContent('')
    setDraft(null)
    setBedLayout(null)

    let fullContent = ''

    abortRef.current = streamPlanner(text, context || {}, (event: SSEEvent) => {
      if (event.type === 'chunk' && event.content) {
        fullContent += event.content
        setStreamContent(fullContent)
      } else if (event.type === 'draft') {
        setDraft(event.draft as DraftPlan)
      } else if (event.type === 'bed_layout') {
        setBedLayout(event.bed_layout as BedLayout)
      } else if (event.type === 'error') {
        toast.error(String(event.content || 'AI error — try again'))
        setStreaming(false)
      } else if (event.type === 'done') {
        setMessages(prev => [...prev, { role: 'assistant', content: fullContent }])
        setStreamContent('')
        setStreaming(false)
      }
    })
  }, [input, streaming, context])

  const commitDraft = useCallback(async () => {
    if (!draft) return
    setCommitting(true)
    try {
      const res = await fetch('/api/planner/commit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(draft),
      })
      if (!res.ok) throw new Error(await res.text())
      toast.success('Plan applied!')
      setDraft(null)
      onDraftApplied?.()
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to apply plan')
    } finally {
      setCommitting(false)
    }
  }, [draft, onDraftApplied])

  const applyLayout = useCallback(async () => {
    if (!bedLayout) return
    setCommitting(true)
    try {
      const bedsRes = await fetch('/api/beds')
      const beds = await bedsRes.json()
      const bed = beds.find((b: { name: string }) => b.name === bedLayout.bed_name)
      if (!bed) throw new Error(`Bed "${bedLayout.bed_name}" not found`)

      const res = await fetch(`/beds/${bed.id}/apply-layout`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(bedLayout),
      })
      if (!res.ok) throw new Error(await res.text())
      toast.success(`Layout applied to ${bedLayout.bed_name}!`)
      setBedLayout(null)
      onDraftApplied?.()
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to apply layout')
    } finally {
      setCommitting(false)
    }
  }, [bedLayout, onDraftApplied])

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      sendMessage()
    }
    if (e.key === 'Escape') {
      if (streaming && abortRef.current) {
        abortRef.current()
        setStreaming(false)
      } else {
        onClose()
      }
    }
  }

  if (!open) return null

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
      <div className="absolute inset-0 bg-green-900/30 backdrop-blur-sm" onClick={onClose} />

      <div
        className="relative w-full sm:max-w-lg bg-white rounded-t-2xl sm:rounded-2xl shadow-2xl flex flex-col overflow-hidden"
        style={{ maxHeight: '80dvh', animation: 'slideUp 250ms ease-out' }}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-[var(--color-border)]">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-emerald-400 to-green-600 flex items-center justify-center">
              <Sparkles size={16} className="text-white" />
            </div>
            <div>
              <h3 className="text-sm font-semibold" style={{ fontFamily: 'Lora, serif', color: 'var(--color-primary-dark)' }}>
                Garden AI
              </h3>
              <p className="text-xs text-[var(--color-muted)]">Companion planting & bed planning</p>
            </div>
          </div>
          <button onClick={onClose} className="btn-ghost p-2 min-h-0 min-w-0">
            <X size={18} />
          </button>
        </div>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4" style={{ minHeight: 200 }}>
          {messages.length === 0 && !streaming && (
            <div className="text-center py-8">
              <div className="w-12 h-12 mx-auto mb-3 rounded-full bg-gradient-to-br from-emerald-100 to-green-200 flex items-center justify-center">
                <Sparkles size={22} className="text-green-600" />
              </div>
              <p className="text-sm font-medium" style={{ color: 'var(--color-primary-dark)' }}>
                What would you like to plan?
              </p>
              <p className="text-xs text-[var(--color-muted)] mt-1 mb-5">
                I can suggest bed layouts, companion planting, and sowing schedules
              </p>
              <div className="flex flex-wrap gap-2 justify-center">
                {[
                  'What should I plant in BB1?',
                  'Suggest companions for tomatoes',
                  'Plan my spring sowing schedule',
                  'Which beds need attention?',
                ].map(q => (
                  <button
                    key={q}
                    onClick={() => sendMessage(q)}
                    className="text-xs px-3 py-2 rounded-xl border border-[var(--color-border)] text-[var(--color-primary)] hover:bg-[var(--color-card-hover)] hover:border-[var(--color-primary-light)] transition-all cursor-pointer"
                  >
                    {q}
                  </button>
                ))}
              </div>
            </div>
          )}

          {messages.map((msg, i) => (
            <div key={i} className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}>
              <div
                className={`max-w-[85%] px-4 py-2.5 rounded-2xl text-sm leading-relaxed ${
                  msg.role === 'user'
                    ? 'bg-[var(--color-primary)] text-white rounded-br-md'
                    : 'bg-gray-50 text-[var(--color-fg)] rounded-bl-md border border-gray-100'
                }`}
              >
                {msg.role === 'assistant' ? <SafeMarkdown content={msg.content} /> : msg.content}
              </div>
            </div>
          ))}

          {streaming && streamContent && (
            <div className="flex justify-start">
              <div className="max-w-[85%] px-4 py-2.5 rounded-2xl rounded-bl-md bg-gray-50 border border-gray-100 text-sm leading-relaxed">
                <SafeMarkdown content={streamContent} />
                <span className="inline-block w-1.5 h-4 ml-0.5 bg-[var(--color-primary)] animate-pulse rounded-full" />
              </div>
            </div>
          )}

          {streaming && !streamContent && (
            <div className="flex justify-start">
              <div className="px-4 py-3 rounded-2xl rounded-bl-md bg-gray-50 border border-gray-100 flex items-center gap-2">
                <Loader2 size={14} className="animate-spin text-[var(--color-primary)]" />
                <span className="text-sm text-[var(--color-muted)]">Thinking...</span>
              </div>
            </div>
          )}

          {/* Draft plan card */}
          {draft && (
            <div className="bg-green-50 border border-green-200 rounded-2xl p-4">
              <h4 className="text-sm font-semibold text-green-800 mb-2 flex items-center gap-1.5">
                <CheckCircle size={14} /> Plan ready to apply
              </h4>
              {draft.assignments && draft.assignments.length > 0 && (
                <p className="text-xs text-green-700 mb-1">{draft.assignments.length} plant assignments</p>
              )}
              {draft.tasks && draft.tasks.length > 0 && (
                <p className="text-xs text-green-700 mb-1">{draft.tasks.length} tasks</p>
              )}
              <div className="flex gap-2 mt-3">
                <button onClick={commitDraft} disabled={committing} className="btn-primary text-xs py-2 px-4 min-h-0">
                  {committing ? <Loader2 size={14} className="animate-spin" /> : 'Apply plan'}
                </button>
                <button onClick={() => setDraft(null)} className="btn-ghost text-xs py-2 px-3 min-h-0">Dismiss</button>
              </div>
            </div>
          )}

          {/* Bed layout card */}
          {bedLayout && (
            <div className="bg-blue-50 border border-blue-200 rounded-2xl p-4">
              <h4 className="text-sm font-semibold text-blue-800 mb-2">Layout for {bedLayout.bed_name}</h4>
              {bedLayout.suggestions && (
                <p className="text-xs text-blue-700 mb-1">{bedLayout.suggestions.length} plants to place</p>
              )}
              {bedLayout.moves && (
                <p className="text-xs text-blue-700 mb-1">{bedLayout.moves.length} plants to rearrange</p>
              )}
              <div className="flex gap-2 mt-3">
                <button onClick={applyLayout} disabled={committing} className="btn-primary text-xs py-2 px-4 min-h-0">
                  {committing ? <Loader2 size={14} className="animate-spin" /> : 'Apply layout'}
                </button>
                <button onClick={() => setBedLayout(null)} className="btn-ghost text-xs py-2 px-3 min-h-0">Dismiss</button>
              </div>
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>

        {/* Input */}
        <div className="px-4 py-3 border-t border-[var(--color-border)] bg-white">
          <div className="flex items-center gap-2">
            <input
              ref={inputRef}
              type="text"
              value={input}
              onChange={e => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Ask about your garden..."
              className="flex-1 px-4 py-3 rounded-xl border border-[var(--color-border)] text-sm bg-gray-50 focus:bg-white focus:border-[var(--color-primary-light)] outline-none transition-all"
              disabled={streaming}
            />
            <button
              onClick={() => sendMessage()}
              disabled={!input.trim() || streaming}
              className="btn-primary p-3 min-h-[44px] min-w-[44px] disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {streaming ? <Loader2 size={18} className="animate-spin" /> : <Send size={18} />}
            </button>
          </div>
        </div>
      </div>

      <style>{`
        @keyframes slideUp {
          from { opacity: 0; transform: translateY(24px); }
          to { opacity: 1; transform: translateY(0); }
        }
      `}</style>
    </div>
  )
}

export function AIFab({ onClick }: { onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="fixed z-40 shadow-lg hover:shadow-xl transition-all hover:scale-105 active:scale-95"
      style={{
        bottom: 'calc(80px + env(safe-area-inset-bottom, 0px))',
        right: '16px',
        width: 52,
        height: 52,
        borderRadius: 'var(--radius-xl)',
        background: 'linear-gradient(135deg, var(--color-primary-light), var(--color-primary))',
        border: 'none',
        cursor: 'pointer',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
      aria-label="Open AI assistant"
    >
      <Sparkles size={22} className="text-white" />
    </button>
  )
}
