const navToggle=document.getElementById('navToggle');
const sideNav=document.getElementById('sideNav');
if(navToggle&&sideNav){navToggle.addEventListener('click',()=>sideNav.classList.toggle('open'));}
const box=document.getElementById('searchBox');
const results=document.getElementById('searchResults');
if(box&&results&&window.OREN_DOC_SEARCH_INDEX){
  box.addEventListener('input',()=>{
    const q=box.value.trim().toLowerCase();
    results.innerHTML='';
    if(q.length<2)return;
    const hits=window.OREN_DOC_SEARCH_INDEX.filter(p=>(p.title+' '+p.text).toLowerCase().includes(q)).slice(0,8);
    for(const h of hits){
      const a=document.createElement('a');
      a.href=h.href;
      a.className='search-hit';
      a.textContent=h.title;
      results.appendChild(a);
    }
  });
}
