/* Easy multi-student selection for shared lessons; keeps the native select as the form value source. */
window.AlKhubaraStudentPicker=function(id){
 const select=document.getElementById(id);
 if(!select)return {refresh(){}};
 select.hidden=true;select.setAttribute('aria-hidden','true');select.tabIndex=-1;
 const root=document.createElement('section');root.className='student-picker';root.setAttribute('aria-label','اختيار طلاب الحصة');
 const search=document.createElement('input');search.type='search';search.placeholder='ابحث باسم الطالب...';search.className='student-picker-search';search.setAttribute('aria-label','بحث الطلاب');
 const summary=document.createElement('div');summary.className='student-picker-count';summary.setAttribute('aria-live','polite');
 const list=document.createElement('div');list.className='student-picker-list';list.setAttribute('role','group');list.setAttribute('aria-label','الطلاب المتاحون');
 root.append(search,summary,list);select.after(root);
 function count(){const n=[...select.options].filter(x=>x.selected&&x.value).length;summary.textContent='تم اختيار '+n+' طلاب (من 2 إلى 10)';summary.style.color=n>=2&&n<=10?'#176b4c':'#9c6a2b'}
 function refresh(){list.replaceChildren();const q=search.value.trim().toLocaleLowerCase('ar');let matches=0;
  for(const opt of [...select.options].filter(x=>x.value)){if(q&&!opt.textContent.toLocaleLowerCase('ar').includes(q))continue;matches++;
   const label=document.createElement('label');label.className='student-picker-option';const check=document.createElement('input');check.type='checkbox';check.checked=opt.selected;check.setAttribute('aria-label',opt.textContent);
   check.onchange=()=>{if(check.checked&&[...select.selectedOptions].filter(x=>x.value).length>=10){check.checked=false;summary.textContent='الحد الأقصى 10 طلاب';summary.style.color='#b5372d';return}opt.selected=check.checked;count();select.dispatchEvent(new Event('change',{bubbles:true}))};
   const name=document.createElement('span');name.textContent=opt.textContent;label.append(check,name);list.append(label)
  }
  if(!matches){const empty=document.createElement('p');empty.className='student-picker-empty';empty.textContent='لا توجد أسماء مطابقة';list.append(empty)}
  count();
 }
 search.addEventListener('input',refresh);refresh();return{refresh,clear(){search.value='';for(const opt of select.options)opt.selected=false;refresh()}};
};