import { marked } from 'marked'
import DOMPurify from 'dompurify'

marked.setOptions({ breaks: true, gfm: true })

/** Render markdown to sanitized HTML */
export function renderMarkdown(content: string): string {
  const raw = marked.parse(content) as string
  return DOMPurify.sanitize(raw)
}
