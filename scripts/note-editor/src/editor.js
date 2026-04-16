import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import Placeholder from '@tiptap/extension-placeholder'
import BubbleMenu from '@tiptap/extension-bubble-menu'
import TurndownService from 'turndown'
import { marked } from 'marked'
import DOMPurify from 'dompurify'

import './editor.css'

// --- Markdown conversion ---

const turndownService = new TurndownService({
  headingStyle: 'atx',
  bulletListMarker: '-',
  codeBlockStyle: 'fenced',
  emDelimiter: '*',
})

// Custom rule: keep strikethrough
turndownService.addRule('strikethrough', {
  filter: ['del', 's'],
  replacement: (content) => `~~${content}~~`,
})

function htmlToMarkdown(html) {
  if (!html || html === '<p></p>') return ''
  return turndownService.turndown(html).trim()
}

function markdownToHtml(md) {
  if (!md) return '<p></p>'
  const raw = marked.parse(md, { breaks: false, gfm: true })
  return DOMPurify.sanitize(raw, {
    ALLOWED_TAGS: [
      'p', 'br', 'hr',
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'ul', 'ol', 'li',
      'blockquote', 'pre', 'code',
      'em', 'strong', 'del', 's',
      'a', 'span',
    ],
    ALLOWED_ATTR: ['href', 'target', 'rel'],
    ALLOWED_URI_REGEXP: /^(?:https?|mailto):/i,
  })
}

// --- Editor setup ---

let editor = null
let bubbleMenuElement = null

function createBubbleMenu() {
  const el = document.createElement('div')
  el.className = 'note-bubble-menu'
  el.innerHTML = `
    <button data-cmd="bold" title="加粗 (⌘B)"><strong>B</strong></button>
    <button data-cmd="italic" title="斜体 (⌘I)"><em>I</em></button>
    <button data-cmd="strike" title="删除线"><s>S</s></button>
    <button data-cmd="code" title="行内代码"><code>&lt;/&gt;</code></button>
    <span class="sep"></span>
    <button data-cmd="bulletList" title="无序列表">•</button>
    <button data-cmd="orderedList" title="有序列表">1.</button>
    <button data-cmd="blockquote" title="引用">❝</button>
    <span class="sep"></span>
    <button data-cmd="link" title="链接">🔗</button>
  `
  el.addEventListener('mousedown', (e) => e.preventDefault())
  el.addEventListener('click', (e) => {
    const btn = e.target.closest('button')
    if (!btn) return
    const cmd = btn.dataset.cmd
    handleCommand(cmd)
  })
  document.body.appendChild(el)
  return el
}

function handleCommand(cmd) {
  if (!editor) return
  switch (cmd) {
    case 'bold': editor.chain().focus().toggleBold().run(); break
    case 'italic': editor.chain().focus().toggleItalic().run(); break
    case 'strike': editor.chain().focus().toggleStrike().run(); break
    case 'code': editor.chain().focus().toggleCode().run(); break
    case 'bulletList': editor.chain().focus().toggleBulletList().run(); break
    case 'orderedList': editor.chain().focus().toggleOrderedList().run(); break
    case 'blockquote': editor.chain().focus().toggleBlockquote().run(); break
    case 'link': {
      const prev = editor.getAttributes('link').href || ''
      const url = prompt('输入链接地址：', prev)
      if (url === null) return
      if (url === '') {
        editor.chain().focus().unsetLink().run()
      } else {
        editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run()
      }
      break
    }
  }
  updateBubbleMenuActive()
}

function updateBubbleMenuActive() {
  if (!editor || !bubbleMenuElement) return
  bubbleMenuElement.querySelectorAll('button[data-cmd]').forEach((btn) => {
    const cmd = btn.dataset.cmd
    let active = false
    switch (cmd) {
      case 'bold': active = editor.isActive('bold'); break
      case 'italic': active = editor.isActive('italic'); break
      case 'strike': active = editor.isActive('strike'); break
      case 'code': active = editor.isActive('code'); break
      case 'bulletList': active = editor.isActive('bulletList'); break
      case 'orderedList': active = editor.isActive('orderedList'); break
      case 'blockquote': active = editor.isActive('blockquote'); break
      case 'link': active = editor.isActive('link'); break
    }
    btn.classList.toggle('is-active', active)
  })
}

// --- Content height reporting ---

let lastReportedHeight = 0
let _noteDebounceTimer = null

function reportContentHeight() {
  const el = editor?.view?.dom
  if (!el) return
  let height = 36 // default: padding (8+8) + one line (~20)
  if (el.children.length > 0) {
    const last = el.children[el.children.length - 1]
    height = last.offsetTop + last.offsetHeight + 8 // +8 for bottom padding
  }
  // Only report if height changed by more than 2px to avoid jitter
  if (Math.abs(height - lastReportedHeight) <= 2) return
  lastReportedHeight = height
  try {
    window.webkit?.messageHandlers?.noteContentHeightChanged?.postMessage({ height })
  } catch (_) {}
}

function initEditor() {
  const editorElement = document.getElementById('editor')
  bubbleMenuElement = createBubbleMenu()

  editor = new Editor({
    element: editorElement,
    extensions: [
      StarterKit.configure({
        heading: { levels: [1, 2, 3] },
      }),
      Link.configure({
        openOnClick: false,
        HTMLAttributes: { target: '_blank', rel: 'noopener' },
      }),
      Placeholder.configure({
        placeholder: '添加笔记…',
      }),
      BubbleMenu.configure({
        element: bubbleMenuElement,
        tippyOptions: {
          duration: [150, 100],
          placement: 'top',
          offset: [0, 8],
        },
      }),
    ],
    content: '',
    autofocus: false,
    editorProps: {
      attributes: {
        class: 'note-editor-content',
      },
    },
    onUpdate: ({ editor: e }) => {
      updateBubbleMenuActive()
      clearTimeout(_noteDebounceTimer)
      _noteDebounceTimer = setTimeout(() => {
        try {
          const md = htmlToMarkdown(e.getHTML())
          window.webkit?.messageHandlers?.noteContentChanged?.postMessage({ markdown: md })
        } catch (_) {}
      }, 200)
      reportContentHeight()
    },
    onSelectionUpdate: () => {
      updateBubbleMenuActive()
    },
    onFocus: () => {
      try {
        window.webkit?.messageHandlers?.noteEditorFocused?.postMessage({})
      } catch (_) {}
    },
    onBlur: () => {
      clearTimeout(_noteDebounceTimer)
      try {
        const md = htmlToMarkdown(editor.getHTML())
        window.webkit?.messageHandlers?.noteEditorBlurred?.postMessage({ markdown: md })
      } catch (_) {}
    },
  })

  // Expose API for Swift bridge
  window.NoteEditor = {
    setMarkdown(md) {
      if (!editor) return
      const html = markdownToHtml(md || '')
      editor.commands.setContent(html)
      // Report height after content change
      requestAnimationFrame(() => reportContentHeight())
    },
    getMarkdown() {
      if (!editor) return ''
      return htmlToMarkdown(editor.getHTML())
    },
    setPlaceholder(text) {
      if (!editor) return
      // Update placeholder via CSS variable
      document.documentElement.style.setProperty('--placeholder-text', `"${text.replace(/"/g, '\\"')}"`)
    },
    setTheme(theme) {
      document.documentElement.setAttribute('data-theme', theme)
    },
    focus() {
      editor?.commands.focus('end')
    },
    blur() {
      editor?.commands.blur()
    },
    clear() {
      editor?.commands.clearContent()
    },
    isEmpty() {
      return editor?.isEmpty ?? true
    },
    setEditable(editable) {
      editor?.setEditable(editable)
    },
  }

  // Notify Swift that editor is ready
  try {
    window.webkit?.messageHandlers?.noteEditorReady?.postMessage({})
  } catch (_) {}

  // Report initial content height
  reportContentHeight()
}

// Init on DOM ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initEditor)
} else {
  initEditor()
}
