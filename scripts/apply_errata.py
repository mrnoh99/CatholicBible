#!/usr/bin/env python3
"""한국천주교주교회의 '성경 정오표'를 본문(knb·knnotes)에 반영한다.

정오표(scripts/bible_errata.json)의 각 항목은
  {book: 약칭, ref: '장,절', before: 현행, after: 수정 후}
형태다. 본문에 해당하는 깨끗한 낱말/띄어쓰기 수정만 적용하며,
각주·소제목·서체·조판(약물/절표시 이동)·따옴표 스타일 항목은 건너뛴다.

  - after 가 이미 본문에 있으면(이미 수정됨) 건너뛴다.
  - before 가 있으면 after 로 교체한다.
  - 따옴표(‘’“”"' 등) 포함 항목은 판본 간 따옴표 스타일 차이로
    오적용 위험이 있어 제외한다.

사용법:  python scripts/apply_errata.py --apply   (미지정 시 건조 실행)
"""

import xlrd
BOOK={'창세':'gn','탈출':'ex','레위':'lv','민수':'nm','신명':'dt','여호':'jos','판관':'jgs','룻':'ru',
'1사무':'1sm','2사무':'2sm','1열왕':'1kgs','2열왕':'2kgs','1역대':'1chr','2역대':'2chr','에즈':'ezr',
'느헤':'neh','토빗':'tb','유딧':'jdt','에스':'est','1마카':'1mc','2마카':'2mc','욥':'jb','시편':'ps',
'잠언':'prv','코헬':'eccl','아가':'sg','지혜':'wis','집회':'sir','이사':'is','예레':'jer','애가':'lam',
'바룩':'bar','에제':'ez','다니':'dn','호세':'hos','요엘':'jl','아모':'am','오바':'ob','요나':'jon',
'미카':'mi','나훔':'na','하바':'hb','스바':'zep','하까':'hg','즈카':'zec','말라':'mal','마태':'mt',
'마르':'mk','루카':'lk','요한':'jn','사도':'acts','로마':'rom','1코린':'1cor','2코린':'2cor','갈라':'gal',
'에페':'eph','필리':'phil','콜로':'col','1테살':'1thes','2테살':'2thes','1티모':'1tm','2티모':'2tm',
'티토':'ti','필레':'phlm','히브':'heb','야고':'jas','1베드':'1pt','2베드':'2pt','1요한':'1jn','유다':'jude','묵시':'rev'}

def rows_xls(f):
    ws=xlrd.open_workbook(f).sheet_by_index(0)
    return [[ws.cell_value(r,c) for c in range(ws.ncols)] for r in range(ws.nrows)]
def rows_xlsx(f):
    ws=openpyxl.load_workbook(f, read_only=True).worksheets[0]
    return [[(c.value if c.value is not None else '') for c in row] for row in ws.iter_rows()]

def collect():
    ent=[]
    for f in sorted(glob.glob('/root/.claude/uploads/3ca4dd50-b297-5f0a-9288-fec4d13c1b6b/*.xls*')):
        rows=rows_xlsx(f) if f.endswith('.xlsx') else rows_xls(f)
        for r in rows:
            c=[str(x).strip() for x in r]
            if len(c)<5: continue
            if c[0] in ('순서','') or c[1] in ('','성경') or '장절' in c[2]: continue
            if not c[1] or not c[2]: continue
            ent.append((c[1],c[2],c[3],c[4]))
    return ent

def parse_ref(ref):
    # 반환: (chapter, [verses])  또는 None (본문 적용 불가)
    if any(k in ref for k in ['각주','소제목','제목','부록','편','끝 문장','중략','앞','(2곳)','(두 번째)','지도']):
        return None
    m=re.match(r'^\s*(\d+)\s*,\s*([\d\.\-]+)', ref)
    if not m: return None
    ch=m.group(1); vpart=m.group(2)
    verses=[]
    for tok in re.split(r'[.\-]', vpart):
        if tok.isdigit(): verses.append(tok)
    return (ch, verses) if verses else None

def clean(s):
    s=s.strip()
    return s

def main(apply=False):
    ent=collect()
    knbD=json.load(open('CatholicBible/Resources/BibleText_knb.json'))
    knnD=json.load(open('CatholicBible/Resources/BibleText_knbnotes.json'))
    stats={'applied_knb':0,'applied_knn':0,'already':0,'notfound':0,'skip':0}
    notfound=[]; applied=[]
    for book,ref,before,after in ent:
        bid=BOOK.get(book)
        pr=parse_ref(ref)
        bf=clean(before); af=clean(after)
        if not bid or not pr or not bf or not af or '……' in bf or '//' in af or '체)' in bf or '체)' in af or '(중략)' in bf:
            stats['skip']+=1; continue
        ch,verses=pr
        hit=False; already=False
        for ed,D in [('knb',knbD),('knn',knnD)]:
            books=D['books']
            if bid not in books or ch not in books[bid]: continue
            for v in verses:
                if v not in books[bid][ch]: continue
                t=books[bid][ch][v]
                if bf in t:
                    if apply: books[bid][ch][v]=t.replace(bf,af)
                    stats['applied_'+ed]+=1; hit=True
                elif af in t:
                    already=True
        if hit: applied.append((book,ref,bf[:20],af[:20]))
        elif already: stats['already']+=1
        else:
            stats['notfound']+=1; notfound.append((book,ref,bf[:28],af[:28]))
    if apply:
        json.dump(knbD, open('CatholicBible/Resources/BibleText_knb.json','w'), ensure_ascii=False, separators=(',',':'))
        json.dump(knnD, open('CatholicBible/Resources/BibleText_knbnotes.json','w'), ensure_ascii=False, separators=(',',':'))
    print('통계:', stats)
    print('적용된 항목:', len(applied))
    print('미발견(본문에 현행 문구 없음) 표본:')
    for x in notfound[:30]: print('   ', x[0], x[1], '|', repr(x[2]), '→', repr(x[3]))
    print('총 미발견:', len(notfound))

if __name__=='__main__':
    main(apply=('--apply' in sys.argv))
