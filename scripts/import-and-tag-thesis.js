#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

function parseArgs(argv) {
  const options = {
    root: '/Users/water/Downloads/硕士论文与小论文的分析与润色优化',
    cli: path.resolve(__dirname, '..', '.build', 'debug', 'swiftlib-cli'),
    style: 'nature',
    outputDirName: 'docx-output',
    collectionName: `thesis-${new Date().toISOString().replace(/[:.]/g, '-')}`,
    keepTemp: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const argument = argv[index];
    switch (argument) {
      case '--root':
        options.root = argv[++index];
        break;
      case '--cli':
        options.cli = argv[++index];
        break;
      case '--style':
        options.style = argv[++index];
        break;
      case '--output-dir-name':
        options.outputDirName = argv[++index];
        break;
      case '--collection-name':
        options.collectionName = argv[++index];
        break;
      case '--keep-temp':
        options.keepTemp = true;
        break;
      default:
        throw new Error(`Unknown argument: ${argument}`);
    }
  }

  return options;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    input: options.input,
    stdio: options.input == null ? ['inherit', 'pipe', 'pipe'] : ['pipe', 'pipe', 'pipe'],
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    const stderr = (result.stderr || '').trim();
    const stdout = (result.stdout || '').trim();
    throw new Error(`${command} ${args.join(' ')} failed with exit code ${result.status}\n${stderr || stdout}`.trim());
  }

  return (result.stdout || '').trim();
}

function ensureFile(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing required file: ${filePath}`);
  }
}

function listChapterFiles(root) {
  return fs.readdirSync(root)
    .filter((name) => /^第.+\.md$/.test(name))
    .sort((lhs, rhs) => lhs.localeCompare(rhs, 'zh-Hans-CN'))
    .map((name) => path.join(root, name));
}

function parseReferenceEntries(markdown) {
  const lines = markdown.split(/\r?\n/);
  const entries = [];
  let current = null;

  for (const line of lines) {
    const match = line.match(/^\[(\d+)\]\s+(.+)$/);
    if (match) {
      if (current) {
        entries.push(current);
      }
      current = {
        number: Number(match[1]),
        text: match[2].trim(),
      };
      continue;
    }

    if (!current) {
      continue;
    }

    if (!line.trim()) {
      entries.push(current);
      current = null;
      continue;
    }

    current.text += ` ${line.trim()}`;
  }

  if (current) {
    entries.push(current);
  }

  if (entries.length === 0) {
    throw new Error('No numbered bibliography entries were found in 参考文献.md');
  }

  return entries;
}

function escapeRis(text) {
  return text.replace(/\r?\n/g, ' ').trim();
}

// ---------------------------------------------------------------------------
// GB/T 7714 citation parser
// Parses entries like:
//   "Schindler D W. Eutrophication...[J]. Science, 1974, 184(4139): 897-899."
//   "秦伯强, 高光, 等. 湖泊富营养化...[J]. 科学通报, 2013, 58(10): 855-864."
//   "Wetzel R G. Limnology...[M]. 3rd ed. San Diego: Academic Press, 2001."
//   "Gliwicz Z M, Pijanowska J. The role...[M]// Sommer U. Plankton Ecology. Berlin: Springer, 1989: 253-296."
// ---------------------------------------------------------------------------

function parseRawAuthors(authorStr) {
  return authorStr
    .split(/,\s*/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0 && !/^(et\s+al\.?|等\.?)$/i.test(s));
}

/**
 * Format a single author token from GB/T 7714 ("Family Initial(s)" or CJK name)
 * into RIS "Family, Given" format so AuthorName.parse() extracts correctly.
 */
function formatAuthorForRis(token) {
  // Pure CJK — keep as-is (single family name, no given)
  if (/^[\u3400-\u9fff]+$/.test(token)) {
    return token;
  }
  // Western: "Surname I I" → "Surname, I I"
  const spaceIdx = token.indexOf(' ');
  if (spaceIdx === -1) return token;
  return `${token.substring(0, spaceIdx)}, ${token.substring(spaceIdx + 1).trim()}`;
}

/**
 * Split a pre-type string ("Authors. Title") at the last ". " or "．"
 * to separate the author list from the title.
 */
function splitAuthorsTitle(preTypeStr) {
  const idx1 = preTypeStr.lastIndexOf('. ');
  const idx2 = preTypeStr.lastIndexOf('．');
  if (idx1 === -1 && idx2 === -1) {
    return { authors: [], title: preTypeStr.trim() };
  }
  const useFullWidth = idx2 > idx1;
  const sepIdx = useFullWidth ? idx2 : idx1;
  const sepLen = useFullWidth ? 1 : 2;
  const authorStr = preTypeStr.substring(0, sepIdx).trim();
  const title = preTypeStr.substring(sepIdx + sepLen).trim();
  return { authors: parseRawAuthors(authorStr), title };
}

function parseJournalFields(postTypeStr, result) {
  // Format after [J]: ". JournalName, Year[, Vol[(Issue)]: SP[-EP]]."
  let s = postTypeStr.replace(/^\.\s*/, '');
  const commaIdx = s.indexOf(',');
  if (commaIdx === -1) return;
  result.journal = s.substring(0, commaIdx).trim();
  s = s.substring(commaIdx + 1).trim();
  // Match: Year[, Vol[(Issue)]: SP[-EP]]
  const m = s.match(/^(\d{4})\s*(?:,\s*(\d+)\s*(?:\(([^)]+)\))?\s*:\s*(\d+)\s*(?:[-\u2013\u2014]\s*(\d+))?)?/);
  if (m) {
    result.year = parseInt(m[1], 10);
    if (m[2]) result.volume = m[2];
    if (m[3]) result.issue = m[3];
    if (m[4]) result.startPage = m[4];
    if (m[5]) result.endPage = m[5];
  }
}

function parseBookFields(postTypeStr, result) {
  // Format after [M]: ". [Edition. ]Place: Publisher, Year."
  let s = postTypeStr.replace(/^\.\s*/, '');
  const editionMatch = s.match(/^(\d+(?:st|nd|rd|th)?\s*(?:ed\.|edn\.|版))\s*\.\s*/i);
  if (editionMatch) {
    result.edition = editionMatch[1].trim();
    s = s.substring(editionMatch[0].length);
  }
  const colonIdx = s.indexOf(':');
  if (colonIdx === -1) return;
  result.place = s.substring(0, colonIdx).trim();
  s = s.substring(colonIdx + 1).trim();
  const lastComma = s.lastIndexOf(',');
  if (lastComma !== -1) {
    result.publisher = s.substring(0, lastComma).trim();
    const yearNum = parseInt(s.substring(lastComma + 1).replace(/\D/g, ''), 10);
    if (yearNum > 1000) result.year = yearNum;
  }
}

function parseChapterFields(postTypeStr, result) {
  // Format after [M]//: " Editors. Book Title. Place: Publisher, Year: SP-EP."
  const s = postTypeStr.trim();
  const parts = s.split('. ').map((p) => p.trim()).filter((p) => p.length > 0);
  if (parts.length < 3) {
    const yearMatch = s.match(/\b(19|20)\d{2}\b/);
    if (yearMatch) result.year = parseInt(yearMatch[0], 10);
    return;
  }
  const placePublisherYearPages = parts[parts.length - 1];
  result.bookTitle = parts[parts.length - 2];
  const colonIdx = placePublisherYearPages.indexOf(':');
  if (colonIdx === -1) return;
  result.place = placePublisherYearPages.substring(0, colonIdx).trim();
  let rest = placePublisherYearPages.substring(colonIdx + 1).trim();
  const commaIdx = rest.indexOf(',');
  if (commaIdx !== -1) {
    result.publisher = rest.substring(0, commaIdx).trim();
    rest = rest.substring(commaIdx + 1).trim();
    const yearPagesMatch = rest.match(/^(\d{4})\s*:\s*(\d+)\s*[-\u2013\u2014]\s*(\d+)/);
    if (yearPagesMatch) {
      result.year = parseInt(yearPagesMatch[1], 10);
      result.startPage = yearPagesMatch[2];
      result.endPage = yearPagesMatch[3];
    } else {
      const yearMatch = rest.match(/\b(\d{4})\b/);
      if (yearMatch) result.year = parseInt(yearMatch[1], 10);
    }
  }
}

function parseThesisFields(postTypeStr, result) {
  // Format after [D]: ". Place: University, Year."
  let s = postTypeStr.replace(/^\.\s*/, '');
  const colonIdx = s.indexOf(':');
  if (colonIdx === -1) return;
  result.place = s.substring(0, colonIdx).trim();
  const rest = s.substring(colonIdx + 1).trim();
  const lastComma = rest.lastIndexOf(',');
  if (lastComma !== -1) {
    result.publisher = rest.substring(0, lastComma).trim();
    const yearNum = parseInt(rest.substring(lastComma + 1).replace(/\D/g, ''), 10);
    if (yearNum > 1000) result.year = yearNum;
  }
}

function parseGBT7714Citation(rawText) {
  const blank = {
    type: 'GEN', title: null, authors: [], year: null,
    journal: null, volume: null, issue: null, startPage: null, endPage: null,
    publisher: null, place: null, edition: null, bookTitle: null,
  };

  // Strip leading ★ and whitespace
  const text = rawText.replace(/^[★\s]+/, '').trim();

  // Detect [M]// (book chapter) before searching for generic [TYPE]
  const chapterMarkerIdx = text.indexOf('[M]//');
  const typeMatch = text.match(/\[([JMDC])\]/);
  if (!typeMatch) {
    return { ...blank, title: text };
  }

  const isChapter = chapterMarkerIdx !== -1;
  const typeCode = typeMatch[1];
  const typeMarkerStr = isChapter ? '[M]//' : typeMatch[0];
  const typeMarkerIdx = isChapter ? chapterMarkerIdx : text.indexOf(typeMatch[0]);

  const preTypeStr = text.substring(0, typeMarkerIdx).trim();
  const postTypeStr = text.substring(typeMarkerIdx + typeMarkerStr.length);

  const { authors, title } = splitAuthorsTitle(preTypeStr);

  const risType = isChapter ? 'CHAP'
    : typeCode === 'J' ? 'JOUR'
    : typeCode === 'M' ? 'BOOK'
    : typeCode === 'D' ? 'THES'
    : typeCode === 'C' ? 'CONF'
    : 'GEN';

  const result = { ...blank, type: risType, title: title || text, authors };

  if (isChapter) parseChapterFields(postTypeStr, result);
  else if (typeCode === 'J') parseJournalFields(postTypeStr, result);
  else if (typeCode === 'M') parseBookFields(postTypeStr, result);
  else if (typeCode === 'D') parseThesisFields(postTypeStr, result);

  return result;
}

function buildRisRecord(entry) {
  let parsed = null;
  try {
    parsed = parseGBT7714Citation(entry.text);
  } catch (_) { /* use fallback */ }

  const useFallback = !parsed || !parsed.title || parsed.title.length < 3;
  if (useFallback) {
    process.stderr.write(`Warning: [${entry.number}] Could not parse title, using full citation as TI\n`);
  }

  const type = useFallback ? 'GEN' : parsed.type;
  const title = useFallback ? entry.text : parsed.title;

  const lines = [
    `TY  - ${type}`,
    `ID  - REF${entry.number}`,
    `TI  - ${escapeRis(title)}`,
  ];

  if (!useFallback) {
    for (const author of parsed.authors) {
      lines.push(`AU  - ${escapeRis(formatAuthorForRis(author))}`);
    }
    if (parsed.year) lines.push(`PY  - ${parsed.year}`);
    if (parsed.journal) lines.push(`JO  - ${escapeRis(parsed.journal)}`);
    if (parsed.volume) lines.push(`VL  - ${parsed.volume}`);
    if (parsed.issue) lines.push(`IS  - ${escapeRis(parsed.issue)}`);
    if (parsed.startPage) lines.push(`SP  - ${parsed.startPage}`);
    if (parsed.endPage) lines.push(`EP  - ${parsed.endPage}`);
    if (parsed.publisher) lines.push(`PB  - ${escapeRis(parsed.publisher)}`);
    if (parsed.place) lines.push(`CY  - ${escapeRis(parsed.place)}`);
    if (parsed.edition) lines.push(`ET  - ${escapeRis(parsed.edition)}`);
    if (parsed.bookTitle) lines.push(`T2  - ${escapeRis(parsed.bookTitle)}`);
  }

  lines.push('ER  - ');
  return lines.join('\n');
}

function buildRis(entries) {
  return entries.map((entry) => buildRisRecord(entry)).join('\n\n') + '\n';
}

function superscriptCitations(markdown) {
  return markdown.replace(/\[(\d+(?:\s*[-–—,]\s*\d+)*)\]/g, '<sup>[$1]</sup>');
}

function writeMergedMarkdown(chapterMarkdown, referenceMarkdown) {
  const body = superscriptCitations(chapterMarkdown.trimEnd());
  return `${body}\n\n# 参考文献\n\n${referenceMarkdown.trim()}\n`;
}

function createCollection(cliPath, name) {
  const raw = run(cliPath, ['collections', '--create', '--name', name]);
  const parsed = JSON.parse(raw);
  const id = Number(parsed.id);
  if (!Number.isFinite(id)) {
    throw new Error(`Failed to parse collection id from CLI output: ${raw}`);
  }
  return { id, name: parsed.name || name };
}

function importReferences(cliPath, risPath, collectionId) {
  const raw = run(cliPath, ['import', risPath, '--collection', String(collectionId)]);
  return JSON.parse(raw);
}

function convertToDocx(markdownPath, docxPath) {
  run('pandoc', [markdownPath, '-o', docxPath]);
}

function tagDocx(cliPath, inputPath, outputPath, style, collectionId) {
  const raw = run(cliPath, [
    'tag-docx',
    inputPath,
    '--output',
    outputPath,
    '--style',
    style,
    '--collection',
    String(collectionId),
  ]);
  return JSON.parse(raw);
}

function main() {
  const options = parseArgs(process.argv);
  const root = path.resolve(options.root);
  const referencePath = path.join(root, '参考文献.md');
  const chapterPaths = listChapterFiles(root);
  const outputDir = path.join(root, options.outputDirName);
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'swiftlib-thesis-'));

  ensureFile(options.cli);
  ensureFile(referencePath);
  if (chapterPaths.length === 0) {
    throw new Error(`No chapter markdown files were found under ${root}`);
  }

  run(options.cli, ['--version']);
  run('pandoc', ['--version']);

  fs.mkdirSync(outputDir, { recursive: true });

  const referenceMarkdown = fs.readFileSync(referencePath, 'utf8');
  const referenceEntries = parseReferenceEntries(referenceMarkdown);
  const risPath = path.join(tempDir, 'references.ris');
  fs.writeFileSync(risPath, buildRis(referenceEntries), 'utf8');

  const collection = createCollection(options.cli, options.collectionName);
  const importReport = importReferences(options.cli, risPath, collection.id);

  const chapterReports = [];
  for (const chapterPath of chapterPaths) {
    const chapterName = path.basename(chapterPath, '.md');
    const mergedMarkdownPath = path.join(tempDir, `${chapterName}.merged.md`);
    const rawDocxPath = path.join(outputDir, `${chapterName}.docx`);
    const taggedDocxPath = path.join(outputDir, `${chapterName}.tagged.docx`);

    const chapterMarkdown = fs.readFileSync(chapterPath, 'utf8');
    const mergedMarkdown = writeMergedMarkdown(chapterMarkdown, referenceMarkdown);
    fs.writeFileSync(mergedMarkdownPath, mergedMarkdown, 'utf8');

    convertToDocx(mergedMarkdownPath, rawDocxPath);
    const tagReport = tagDocx(options.cli, rawDocxPath, taggedDocxPath, options.style, collection.id);

    chapterReports.push({
      chapter: chapterName,
      markdownPath: chapterPath,
      rawDocxPath,
      taggedDocxPath,
      tagReport,
    });
  }

  const summary = {
    root,
    style: options.style,
    collection,
    referenceCount: referenceEntries.length,
    importReport,
    chapterReports,
    outputDir,
    tempDir: options.keepTemp ? tempDir : null,
  };

  const summaryPath = path.join(outputDir, 'import-and-tag-report.json');
  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2), 'utf8');

  if (!options.keepTemp) {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }

  process.stdout.write(`${JSON.stringify({
    summaryPath,
    outputDir,
    collection,
    importedReferenceCount: referenceEntries.length,
    chapterCount: chapterReports.length,
  }, null, 2)}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
}