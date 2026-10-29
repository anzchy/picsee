# -*- coding: utf-8 -*-
# Resolve ledger conflicts limited to Part 3 area-review rows by union: keep HEAD's (main's) row,
# then append each 。-ended entry of the branch's 备注 that main's 备注 doesn't already hold verbatim.
# Entries are compared whole (never by substring or ；-clause), so a branch entry that shares a stock clause
# such as 「待 owner 确认。」 with main is still appended. The newer 最近审查 date wins, with its 审查人.
# Main's notes are never dropped. A row only one side has is kept as is. Line endings are preserved.
# Prints 'ok', or 'UNRESOLVED' and leaves the conflict block when it can't tell rows apart.
import re
import sys


def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


def key(line):
    return cells(line)[0]


def entries(note):
    return [s.strip() for s in re.findall(r'[^。]*。|[^。]+$', note) if s.strip()]


def merge_row(head, theirs):
    if head == theirs:
        return head
    h, t = cells(head), cells(theirs)
    if len(h) != len(t) or len(h) < 4:
        return head
    main_entries = set(entries(h[-1]))
    extra = [s for s in entries(t[-1]) if s not in main_entries]
    note = h[-1] + ''.join(extra)
    date, reviewer = (t[1], t[2]) if t[1] > h[1] else (h[1], h[2])
    return '| ' + ' | '.join([h[0], date, reviewer] + h[3:-1] + [note]) + ' |'


def merge_block(head, theirs):
    if any(not l.startswith('| ') for l in head + theirs if l.strip()):
        return None
    rows = lambda ls: [l for l in ls if l.startswith('| ')]
    tk = {key(l): l for l in rows(theirs)}
    hk = [key(l) for l in rows(head)]
    out = [merge_row(l, tk[key(l)]) if key(l) in tk else l for l in rows(head)]
    out += [l for l in rows(theirs) if key(l) not in hk]
    return out


def resolve(text):
    nl = '\r\n' if '\r\n' in text else '\n'
    s = text.split(nl)
    if s and s[-1] == '':
        s.pop()
    out = []; i = 0; ok = True
    while i < len(s):
        if s[i].startswith('<<<<<<<'):
            j = s.index('=======', i)
            k = next(n for n in range(j, len(s)) if s[n].startswith('>>>>>>>'))
            merged = merge_block(s[i + 1:j], s[j + 1:k])
            if merged is None:
                ok = False; out += s[i:k + 1]
            else:
                out += merged
            i = k + 1; continue
        out.append(s[i]); i += 1
    return nl.join(out) + nl, ok


if __name__ == '__main__':
    p = sys.argv[1]
    with open(p, newline='') as f:
        text, ok = resolve(f.read())
    with open(p, 'w', newline='') as f:
        f.write(text)
    print('ok' if ok else 'UNRESOLVED')
