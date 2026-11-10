/* AlKhubara shared table UX — pagination, row selection and Excel export.
   Applies to all existing rendered tables without replacing their data sources. */
(()=>{"use strict";
const css=`
.kh-table-container{width:100%;max-width:100%}
.kh-table-container table{border-collapse:separate;border-spacing:0;width:100%}
.kh-table-container table thead th{position:sticky;top:0;z-index:1;background:#eaf3ed!important;color:#214d3a;font-weight:800;font-size:12px;border-bottom:2px solid #c8dfd0;white-space:nowrap}
.kh-table-container table tbody tr{transition:background-color .15s}
.kh-table-container table tbody tr:hover{background:#f4f9f5}
.kh-table-container table tbody tr.kh-selected{background:#e9f6ee}
.kh-table-container .kh-check-col{width:40px;min-width:40px;text-align:center!important;padding-inline:8px!important;position:sticky;right:0;background:inherit}
.kh-table-container input.kh-row-check,.kh-table-container input.kh-master-check{width:17px!important;height:17px!important;min-height:0!important;accent-color:#12694f;vertical-align:middle;cursor:pointer}
.kh-footer{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px;padding:12px 6px 2px;border-top:1px solid #e4ede6;margin-top:10px;font-family:Cairo,Tahoma,Arial,sans-serif;direction:rtl}
.kh-footer-group{display:flex;align-items:center;flex-wrap:wrap;gap:8px}
.kh-footer button{min-height:34px!important;padding:5px 11px!important;font-size:12px!important;border:1px solid #cee1d3!important;border-radius:8px!important;background:white!important;color:#1f5840!important}
.kh-footer button.kh-export{background:#12694f!important;color:white!important;border-color:#12694f!important}
.kh-footer button:hover:not(:disabled){background:#e9f4ed!important;color:#125b40!important}
.kh-footer button:disabled{opacity:.45;cursor:not-allowed}
.kh-footer select{width:auto!important;min-width:66px;min-height:34px!important;padding:3px 8px!important;font-size:12px!important;border:1px solid #d3e1d7!important;border-radius:7px!important;background:white}
.kh-footer label,.kh-footer span{font-size:12px!important;color:#5d7868!important;margin:0!important}
.kh-footer .kh-page{font-weight:800;color:#2b5945!important;min-width:68px;text-align:center}
.kh-footer .kh-selected-count{font-weight:700;color:#12694f!important}
@media(max-width:550px){.kh-footer{gap:8px}.kh-footer-group{gap:5px}.kh-footer button{padding:5px 8px!important}}
@media print{.kh-footer,.kh-check-col{display:none!important}}
`;
const style=document.createElement("style");style.textContent=css;document.head.append(style);
const isPeople=()=>location.pathname.endsWith("/people.html");
const isStudentTable=()=>isPeople()&&document.querySelector('[data-kind="students"].active')!==null;
let excelPromise;
function excelLibrary(){
 if(window.ExcelJS)return Promise.resolve(window.ExcelJS);
 if(excelPromise)return excelPromise;
 excelPromise=new Promise((resolve,reject)=>{
  const s=document.createElement("script");s.src="https://cdn.jsdelivr.net/npm/exceljs@4.4.0/dist/exceljs.min.js";
  s.onload=()=>window.ExcelJS?resolve(window.ExcelJS):reject(new Error("ExcelJS unavailable"));
  s.onerror=()=>reject(new Error("تعذر تحميل مكتبة Excel"));
  document.head.append(s)
 }).catch(e=>{excelPromise=null;throw e});
 return excelPromise
}
function init(table,index){
 if(table.dataset.khReady)return;
 const body=table.tBodies[0],head=table.tHead;if(!body||!head)return;
 table.dataset.khReady="1";
 const wrap=table.parentElement;wrap.classList.add("kh-table-container");
 const footer=document.createElement("div");footer.className="kh-footer";
 const right=document.createElement("div");right.className="kh-footer-group";
 const left=document.createElement("div");left.className="kh-footer-group";
 const label=document.createElement("label");label.textContent="عدد الصفوف:";
 const select=document.createElement("select");select.setAttribute("aria-label","عدد الصفوف في الصفحة");
 for(const size of [10,25,50,100]){const o=document.createElement("option");o.value=size;o.textContent=size;select.append(o)}select.value="10";
 const range=document.createElement("span");
 right.append(label,select,range);
 const previous=document.createElement("button");previous.type="button";previous.textContent="السابق";
 const pageText=document.createElement("span");pageText.className="kh-page";
 const next=document.createElement("button");next.type="button";next.textContent="التالي";
 const selectionText=document.createElement("span");selectionText.className="kh-selected-count";
 const exportButton=document.createElement("button");exportButton.type="button";exportButton.className="kh-export";exportButton.textContent="تصدير Excel";
 left.append(previous,pageText,next,selectionText,exportButton);footer.append(right,left);wrap.insertAdjacentElement("afterend",footer);
 let currentPage=1,lock=false,rows=[],selected=new Set(),headRow=null,master=null;
 const visibleRows=()=>Array.from(body.rows).filter(r=>r.cells.length>0&&!r.dataset.khPlaceholder);
 function keepExportRule(){exportButton.hidden=isPeople();exportButton.disabled=exportButton.hidden||!rows.some(r=>!r.dataset.khPlaceholder)}
 function ensureHeader(){
  const header=head.rows[0];if(!header)return;
  if(header!==headRow){headRow=header;master=null}
  if(!header.querySelector(".kh-master-check")){
   const th=document.createElement("th");th.className="kh-check-col";const input=document.createElement("input");input.type="checkbox";input.className="kh-master-check";input.setAttribute("aria-label","تحديد جميع صفوف الصفحة");th.append(input);header.insertBefore(th,header.firstChild);master=input;
   input.addEventListener("change",()=>{for(const r of rows){if(r.style.display==="none")continue;const checkbox=r.querySelector(".kh-row-check");if(!checkbox)continue;checkbox.checked=input.checked;if(input.checked)selected.add(r);else selected.delete(r);r.classList.toggle("kh-selected",input.checked)}updateSelection()})
  }else master=header.querySelector(".kh-master-check");
 }
 function ensureCheckboxes(){
  for(const r of rows){
   if(r.querySelector(".kh-row-check"))continue;
   const td=document.createElement("td");td.className="kh-check-col";
   const input=document.createElement("input");input.type="checkbox";input.className="kh-row-check";input.setAttribute("aria-label","تحديد صف");
   td.append(input);r.insertBefore(td,r.firstChild);
   input.addEventListener("change",()=>{if(input.checked)selected.add(r);else selected.delete(r);r.classList.toggle("kh-selected",input.checked);updateSelection()})
  }
 }
 function updateSelection(){
  selectionText.textContent=selected.size?"تم تحديد "+selected.size:"";
  const current=rows.filter(r=>r.style.display!=="none");
  master.checked=current.length>0&&current.every(r=>selected.has(r));
  master.indeterminate=current.some(r=>selected.has(r))&&!master.checked
 }
 function apply(){
  ensureHeader();const size=Number(select.value),pages=Math.max(1,Math.ceil(rows.length/size));
  currentPage=Math.min(Math.max(1,currentPage),pages);
  const first=(currentPage-1)*size;
  rows.forEach((r,i)=>{r.style.display=i>=first&&i<first+size?"":"none"});
  const start=rows.length?first+1:0,end=Math.min(first+size,rows.length);
  range.textContent=start+"–"+end+" من "+rows.length;
  pageText.textContent="صفحة "+currentPage+" / "+pages;
  previous.disabled=currentPage===1;next.disabled=currentPage>=pages;
  keepExportRule();updateSelection()
 }
 function synchronize(){
  if(lock)return;lock=true;
  try{
   // A record-list refresh replaces the tbody rows. Discard old selections.
   const fresh=visibleRows().filter(r=>r.cells.length>1||r.querySelector(".kh-row-check"));
   if(fresh.length!==rows.length||fresh.some((r,i)=>r!==rows[i])){selected.clear();currentPage=1}
   rows=fresh;
   ensureCheckboxes();apply()
  }finally{lock=false}
 }
 select.onchange=()=>{currentPage=1;apply()};
 previous.onclick=()=>{if(currentPage>1){currentPage--;apply()}};
 next.onclick=()=>{currentPage++;apply()};
 function cleanHeaders(){
  return Array.from(head.rows[0].cells).filter(x=>!x.classList.contains("kh-check-col")&&!/^(?:الإجراءات|إجراء|الاجراءات|actions?)$/i.test(x.textContent.trim()))
 }
 function valuesFrom(r,columns){
  const cells=Array.from(r.cells).filter(c=>!c.classList.contains("kh-check-col"));
  const headings=Array.from(head.rows[0].cells).filter(c=>!c.classList.contains("kh-check-col"));
  return columns.map(col=>{
   const idx=headings.indexOf(col);const cell=cells[idx];
   return cell?(cell.innerText||cell.textContent||"").replace(/\s+/g," ").trim():""
  })
 }
 exportButton.onclick=async()=>{
  if(isStudentTable())return;
  const selectedRows=rows.filter(r=>selected.has(r));
  const exportRows=selectedRows.length?selectedRows:rows;
  const cols=cleanHeaders();
  if(!exportRows.length||!cols.length)return;
  exportButton.disabled=true;exportButton.textContent="جارٍ تجهيز Excel...";
  try{
   const ExcelJS=await excelLibrary();const book=new ExcelJS.Workbook(),sheet=book.addWorksheet("البيانات",{views:[{rightToLeft:true,state:"frozen",ySplit:1}]});
   const headers=cols.map(c=>c.textContent.trim());
   sheet.addRow(headers);
   for(const r of exportRows){sheet.addRow(valuesFrom(r,cols))}
   sheet.columns=headers.map((v,i)=>({width:Math.max(15,Math.min(45,Math.max(v.length+5,...exportRows.slice(0,100).map(r=>valuesFrom(r,cols)[i].length+2))))}));
   const titleRow=sheet.getRow(1);titleRow.height=25;
   titleRow.eachCell(cell=>{cell.fill={type:"pattern",pattern:"solid",fgColor:{argb:"FF17644D"}};cell.font={name:"Arial",size:11,bold:true,color:{argb:"FFFFFFFF"}};cell.alignment={horizontal:"right",vertical:"middle"}});
   sheet.eachRow((row,n)=>{if(n===1)return;row.height=23;row.eachCell(cell=>{cell.font={name:"Arial",size:10,color:{argb:"FF263B30"}};cell.alignment={horizontal:"right",vertical:"middle"};if(n%2===0)cell.fill={type:"pattern",pattern:"solid",fgColor:{argb:"FFF3F8F4"}}})});
   sheet.autoFilter={from:"A1",to:{row:1,column:headers.length}};
   const buffer=await book.xlsx.writeBuffer(),blob=new Blob([buffer],{type:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}),url=URL.createObjectURL(blob);
   const a=document.createElement("a");a.href=url;a.download="AlKhubara_"+(isPeople()?"Teachers":location.pathname.split("/").pop().replace(".html",""))+"_"+new Date().toISOString().slice(0,10)+".xlsx";a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)
  }catch(e){alert("تعذر تصدير Excel: "+e.message)}
  finally{exportButton.textContent="تصدير Excel";keepExportRule()}
 };
 const observer=new MutationObserver(()=>{if(lock)return;queueMicrotask(synchronize)});
 observer.observe(body,{childList:true});observer.observe(head,{childList:true});
 document.querySelectorAll('[data-kind]').forEach(el=>el.addEventListener("click",()=>setTimeout(()=>{selected.clear();synchronize()},0)));
 synchronize()
}
function boot(){document.querySelectorAll("table").forEach(init)}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot,{once:true});else boot();
})();