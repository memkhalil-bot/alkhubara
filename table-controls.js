/* AlKhubara shared tables UI — no privileged data access. */
(() => {
  'use strict';
  const LABEL = 'الكود';
  const controllers = new WeakMap();
  let excelLoader;
  const $el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className=cls; if (text!==undefined) e.textContent=text; return e; };
  const styles = document.createElement('style');
  styles.textContent = `
    .akh-table-tools{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:10px;margin:11px 0 9px;font:600 12px Cairo,Tahoma,Arial,sans-serif}
    .akh-table-right,.akh-table-left,.akh-pages{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
    .akh-table-tools select{width:auto!important;min-width:78px;min-height:36px!important;padding:5px 9px!important;font-size:12px!important}
    .akh-table-tools button{min-height:36px!important;padding:6px 11px!important;font-size:12px!important;border-radius:8px!important;cursor:pointer}
    .akh-table-tools button:disabled{opacity:.45;cursor:not-allowed}
    .akh-export{background:#e7f3e9!important;color:#176144!important;border:1px solid #cce3d3!important}
    .akh-pages button{background:#fff!important;color:#285b46!important;border:1px solid #d6e5da!important;min-width:35px!important}
    .akh-pages button.active{background:#12664f!important;color:#fff!important}
    .akh-table-caption{color:#647d70;font-size:11px}
    table.akh-enhanced{border-collapse:separate!important;border-spacing:0!important}
    table.akh-enhanced thead th{background:#eaf2ec!important;color:#224f3c!important;font-size:12px!important;font-weight:800!important;white-space:nowrap;padding:12px 11px!important;border-bottom:2px solid #aecdb9!important;position:relative}
    table.akh-enhanced tbody tr:hover td{background:#f5faf6}
    table.akh-enhanced tbody tr.akh-selected td{background:#ecf7ef!important}
    table.akh-enhanced td{line-height:1.65}
    table.akh-enhanced th.akh-check,table.akh-enhanced td.akh-check{width:38px!important;min-width:38px!important;text-align:center!important}
    table.akh-enhanced .akh-check input{accent-color:#157556;width:16px;height:16px;min-height:0!important}
    .akh-table-tools button:focus-visible,.akh-table-tools select:focus-visible,.akh-check input:focus-visible{outline:2px solid #e8ab45;outline-offset:2px}
    @media print{.akh-table-tools,.akh-check{display:none!important}table.akh-enhanced tbody tr[hidden]{display:table-row!important}table.akh-enhanced thead th{position:static}}
  `;
  document.head.append(styles);

  function titleFor(table) {
    const panel=table.closest('.panel,.card')||table.parentElement;
    return panel?.querySelector('h2,h3')?.textContent?.trim()||'جدول';
  }
  function isStudentTable(table) {
    return table.closest('#app') && table.closest('body')?.querySelector('[data-kind="students"].active') &&
      !!table.closest('.panel')?.querySelector('#listTitle') && table.closest('.panel')?.querySelector('#listTitle')?.textContent?.includes('الطلاب');
  }
  const isSensitiveColumn = h => /^(الهاتف|رقم الهاتف|رقم التليفون|التليفون|الجوال|البريد|البريد الإلكتروني|الإيميل|الايميل)$/u.test(h.trim());
  function updateSensitive(table) {
    if (!table.closest('body')?.querySelector('#listTitle')) return;
    if (!table.closest('.panel')?.querySelector('#listTitle')) return;
    const heading=table.tHead?.rows[0], rows=[...table.tBodies[0]?.rows||[]]; if(!heading) return;
    const headings=[...heading.cells].filter(x=>!x.classList.contains('akh-check'));
    const positions=headings.map((h,i)=>isSensitiveColumn(h.textContent)?i:-1).filter(i=>i>=0);
    for (const i of positions) {
      if(headings[i]) headings[i].style.display='none';
      for (const row of rows) {
        const cells=[...row.cells].filter(x=>!x.classList.contains('akh-check'));
        if(cells[i])cells[i].style.display='none';
      }
    }
  }
  async function ensureExcel() {
    if(window.ExcelJS)return window.ExcelJS;
    if(!excelLoader)excelLoader=new Promise((resolve,reject)=>{
      const script=document.createElement('script');
      script.src='https://cdn.jsdelivr.net/npm/exceljs@4.4.0/dist/exceljs.min.js';
      script.onload=()=>window.ExcelJS?resolve(window.ExcelJS):reject(new Error('تعذر تحميل Excel'));
      script.onerror=()=>reject(new Error('تعذر الاتصال بمكتبة Excel'));
      document.head.append(script);
    });
    return excelLoader;
  }
  function triggerFile(bytes,fileName){
    const href=URL.createObjectURL(new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}));
    const a=$el('a');a.href=href;a.download=fileName;document.body.append(a);a.click();a.remove();
    setTimeout(()=>URL.revokeObjectURL(href),1500);
  }
  function setup(table) {
    if(controllers.has(table)||!table.tBodies[0])return;
    const tbody=table.tBodies[0],parent=table.closest('.wrap,.tablewrap')||table.parentElement;
    const bar=$el('div','akh-table-tools');bar.setAttribute('role','group');bar.setAttribute('aria-label','خيارات عرض الجدول');
    const right=$el('div','akh-table-right'),left=$el('div','akh-table-left');
    const label=$el('span','akh-table-caption','عرض'); const size=$el('select');
    for(const v of [10,25,50,100]){const o=$el('option',null,String(v));o.value=String(v);size.append(o)}
    size.value='10';size.setAttribute('aria-label','عدد الصفوف في الصفحة');
    const count=$el('span','akh-table-caption');right.append(label,size,count);
    const exportButton=$el('button','akh-export','تصدير Excel');
    exportButton.type='button';left.append(exportButton);bar.append(right,left);
    parent.parentElement?.insertBefore(bar,parent.nextSibling);
    const pager=$el('div','akh-table-tools');pager.setAttribute('aria-label','ترقيم صفحات الجدول');
    const info=$el('span','akh-table-caption'),pages=$el('div','akh-pages');pager.append(info,pages);
    bar.parentElement?.insertBefore(pager,bar.nextSibling);
    table.classList.add('akh-enhanced');
    const selected=new Set();let page=1,total=0,pending=false,observer;
    function dataRows(){return [...tbody.rows].filter(r=>!r.dataset.akhPlaceholder)}
    function displayRows(){return dataRows().filter(r=>!r.dataset.akhEmpty)}
    function rowsHeaders(){return [...(table.tHead?.rows[0]?.cells||[])].filter(c=>!c.classList.contains('akh-check'))}
    function checkColumns(){
      if(table.tHead?.rows[0]&&!table.tHead.rows[0].querySelector('.akh-check')){
        const th=$el('th','akh-check');const control=$el('input');control.type='checkbox';control.setAttribute('aria-label','تحديد كل الصفوف في الصفحة');
        th.append(control);table.tHead.rows[0].prepend(th);control.onchange=()=>{for(const r of displayRows().filter(x=>!x.hidden)){const check=r.querySelector('td.akh-check input');if(check){check.checked=control.checked;check.dispatchEvent(new Event('change'))}}};
      }
      for(const [i,r] of dataRows().entries()){
        if(r.querySelector('.akh-check'))continue;
        const td=$el('td','akh-check'),input=$el('input');input.type='checkbox';input.setAttribute('aria-label','تحديد الصف '+(i+1));
        td.append(input);r.prepend(td);
        const rowKey=r.dataset.akhKey||(r.dataset.akhKey='row-'+i+'-'+(r.cells[1]?.textContent||''));
        input.checked=selected.has(rowKey);
        input.onchange=()=>{if(input.checked)selected.add(rowKey);else selected.delete(rowKey);r.classList.toggle('akh-selected',input.checked);refreshHeader()};
      }
    }
    function refreshHeader(){const all=table.tHead?.rows[0]?.querySelector('.akh-check input');if(!all)return;
      const visible=displayRows().filter(r=>!r.hidden).map(r=>r.querySelector('td.akh-check input')).filter(Boolean);
      all.checked=visible.length>0&&visible.every(c=>c.checked);all.indeterminate=visible.some(c=>c.checked)&&!all.checked;
    }
    function redraw(){
      observer?.disconnect();
      try{
        checkColumns();updateSensitive(table);
        const all=displayRows();total=all.length;
        const sizeNumber=Number(size.value);const max=Math.max(1,Math.ceil(total/sizeNumber));page=Math.min(page,max);
        all.forEach((r,i)=>{r.hidden=i<(page-1)*sizeNumber||i>=page*sizeNumber;r.style.display=r.hidden?'none':'';r.classList.toggle('akh-selected',!!r.querySelector('.akh-check input:checked'))});
        count.textContent=total+' سجل';info.textContent=total?(Math.min(total,(page-1)*sizeNumber+1)+'–'+Math.min(total,page*sizeNumber)+' من '+total):'لا توجد سجلات';
        pages.replaceChildren();
        const add=(text,to,disabled,active)=>{const b=$el('button',active?'active':'',String(text));b.type='button';b.disabled=disabled;b.onclick=()=>{page=to;redraw()};pages.append(b)};
        add('السابق',page-1,page===1,false);
        const pageChoices=[...new Set([1,page-1,page,page+1,max].filter(n=>n>=1&&n<=max))].sort((a,b)=>a-b);
        for(const p of pageChoices)add(p,p,false,p===page);
        add('التالي',page+1,page===max,false);
        exportButton.hidden=isStudentTable(table);refreshHeader();
      }finally{observer?.observe(table,{childList:true,subtree:true})}
    }
    function schedule(){if(pending)return;pending=true;queueMicrotask(()=>{pending=false;page=1;selected.clear();redraw()})}
    observer=new MutationObserver(schedule);observer.observe(table,{childList:true,subtree:true});
    size.onchange=()=>{page=1;redraw()};
    exportButton.onclick=async()=>{
      if(isStudentTable(table))return;
      const previous=exportButton.textContent;exportButton.disabled=true;exportButton.textContent='جارٍ تجهيز Excel...';
      try{
        const ExcelJS=await ensureExcel();const book=new ExcelJS.Workbook(),sheet=book.addWorksheet('البيانات',{views:[{state:'frozen',ySplit:1}]});
        const headers=rowsHeaders().filter(c=>c.style.display!=='none'&&!c.hidden).map(c=>c.textContent.trim());
        sheet.addRow(headers);
        let source=displayRows();const chosen=source.filter(r=>r.querySelector('td.akh-check input')?.checked);if(chosen.length)source=chosen;
        for(const r of source)sheet.addRow([...r.cells].filter(c=>!c.classList.contains('akh-check')&&c.style.display!=='none').map(c=>c.textContent.trim()));
        sheet.getRow(1).eachCell(c=>{c.fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF174E3C'}};c.font={bold:true,color:{argb:'FFFFFFFF'},name:'Arial',size:11};c.alignment={vertical:'middle',horizontal:'right'};c.border={bottom:{style:'medium',color:{argb:'FFDCAC58'}}}});
        sheet.getRow(1).height=28;
        for(let i=1;i<=headers.length;i++){const column=sheet.getColumn(i);column.width=Math.min(43,Math.max(14,headers[i-1].length+13));column.alignment={vertical:'middle',horizontal:'right',wrapText:true}}
        for(let row=2;row<=sheet.rowCount;row++){sheet.getRow(row).height=22;if(row%2===0)sheet.getRow(row).eachCell(c=>{c.fill={type:'pattern',pattern:'solid',fgColor:{argb:'FFF1F7F2'}}})}
        sheet.autoFilter={from:{row:1,column:1},to:{row:Math.max(1,sheet.rowCount),column:Math.max(1,headers.length)}};
        sheet.pageSetup={orientation:'landscape',fitToPage:true,fitToWidth:1,fitToHeight:0,paperSize:9};
        const bytes=await book.xlsx.writeBuffer();triggerFile(bytes,'AlKhubara_'+titleFor(table).replace(/[\\/:*?"<>|\s]+/g,'_')+'.xlsx');
      }catch(err){alert('تعذر تصدير الجدول: '+err.message)}
      finally{exportButton.disabled=false;exportButton.textContent=previous}
    };
    controllers.set(table,{redraw});redraw();
  }
  function scan(){document.querySelectorAll('table').forEach(setup)}
  scan();const mainObserver=new MutationObserver(scan);mainObserver.observe(document.body,{childList:true,subtree:false});
  // Tables can be mounted after access verification.
  const app=document.querySelector('#app');if(app)mainObserver.observe(app,{childList:true,subtree:false});
  document.addEventListener('akh:table-refresh',()=>document.querySelectorAll('table').forEach(t=>controllers.get(t)?.redraw()));
})();
