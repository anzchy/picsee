# -*- coding: utf-8 -*-
# Resolve ledger conflicts limited to Part 3 area-review rows by union: keep HEAD's (main's) row,
# then append each 。/；-ended sentence of the branch's 备注 that main's 备注 doesn't already contain.
# Main's notes and dates are never dropped. A row only one side has is kept as is.
# Prints 'ok', or 'UNRESOLVED' and leaves the conflict block when it can't tell rows apart.
import re
import sys


def key(line):
    return line.split('|')[1].strip()


def note(line):
    return line.rstrip().rstrip('|').split('|')[-1]


def merge_row(head, theirs):
    if head == theirs:
        return head
    main_note = note(head)
    extra = [s for s in re.split(r'(?<=[。；])', note(theirs)) if s.strip() and s.strip() not in main_note]
    if not extra:
        return head
    return head.rstrip().rstrip('|').rstrip() + ''.join(extra) + ' |'


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
    s = text.splitlines(); out = []; i = 0; ok = True
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
    return '\n'.join(out) + '\n', ok


if __name__ == '__main__':
    p = sys.argv[1]
    text, ok = resolve(open(p).read())
    open(p, 'w').write(text); print('ok' if ok else 'UNRESOLVED')
