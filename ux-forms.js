/* Shared sign-in and account-form usability enhancements. */
(()=>{'use strict';
function enhancePassword(input){
 if(input.dataset.khPasswordReady || input.closest('.password-wrap') || input.parentElement?.querySelector('.eye-toggle'))return;
 input.dataset.khPasswordReady='1';
 const holder=document.createElement('div');
 holder.className='kh-password-field';
 input.parentNode.insertBefore(holder,input);
 holder.append(input);
 const toggle=document.createElement('button');
 toggle.type='button';toggle.className='kh-password-toggle';
 toggle.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/><path class="eye-slash" d="M3 3l18 18"/></svg>';toggle.title='إظهار كلمة المرور';toggle.setAttribute('aria-label','إظهار كلمة المرور');
 toggle.setAttribute('aria-pressed','false');
 toggle.addEventListener('click',()=>{
   const reveal=input.type==='password';
   input.type=reveal?'text':'password';
   toggle.querySelector('.eye-slash').style.display=reveal?'none':'';toggle.title=reveal?'إخفاء كلمة المرور':'إظهار كلمة المرور';
   toggle.setAttribute('aria-pressed',String(reveal));
   toggle.setAttribute('aria-label',reveal?'إخفاء كلمة المرور':'إظهار كلمة المرور');
   input.focus({preventScroll:true});
 });
 holder.append(toggle);
}
function enhance(){
 for(const input of document.querySelectorAll('input[type="password"]'))enhancePassword(input);
 for(const form of document.querySelectorAll('form')){
   if(form.dataset.khFormReady)return;
   form.dataset.khFormReady='1';
   form.addEventListener('invalid',event=>{
      const field=event.target;
      if(!field||!field.matches?.('input,select,textarea'))return;
      field.setAttribute('aria-invalid','true');
   },true);
   form.addEventListener('input',event=>{
      const field=event.target;
      if(field?.hasAttribute?.('aria-invalid')&&field.validity?.valid)field.removeAttribute('aria-invalid');
   });
 }
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',enhance,{once:true});else enhance();
})();
