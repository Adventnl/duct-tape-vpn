const {chromium}=require('playwright');
const path=require('path');
(async()=>{const browser=await chromium.launch({headless:true,executablePath:process.env.DUCT_CHROMIUM||undefined,args:['--no-sandbox']});
for(const [name,w,h,dark,large] of [['desktop',440,640,false,false],['mobile',390,844,false,false],['dark',390,844,true,false],['large-text',320,720,false,true]]){
 const page=await browser.newPage({viewport:{width:w,height:h},colorScheme:dark?'dark':'light',reducedMotion:'reduce'});
 await page.goto('file://'+path.resolve('docs/design/concept.html'));
 if(large)await page.evaluate(()=>document.body.classList.add('large'));
 await page.screenshot({path:`docs/design/${name}.png`,fullPage:true});
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);if(overflow)throw new Error('Horizontal overflow '+name);
 console.log('Rendered concept',name,w,h);await page.close();
}await browser.close()})().catch(e=>{console.error(e.message);process.exit(1)});
