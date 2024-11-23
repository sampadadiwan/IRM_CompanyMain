import*as e from"node-gyp-build";var r={};
/**
 * Checks if a given buffer contains only correct UTF-8.
 * Ported from https://www.cl.cam.ac.uk/%7Emgk25/ucs/utf8_check.c by
 * Markus Kuhn.
 *
 * @param {Buffer} buf The buffer to check
 * @return {Boolean} `true` if `buf` contains only correct UTF-8, else `false`
 * @public
 */function isValidUTF8(e){const r=e.length;let t=0;while(t<r)if((e[t]&128)===0)t++;else if((e[t]&224)===192){if(t+1===r||(e[t+1]&192)!==128||(e[t]&254)===192)return false;t+=2}else if((e[t]&240)===224){if(t+2>=r||(e[t+1]&192)!==128||(e[t+2]&192)!==128||e[t]===224&&(e[t+1]&224)===128||e[t]===237&&(e[t+1]&224)===160)return false;t+=3}else{if((e[t]&248)!==240)return false;if(t+3>=r||(e[t+1]&192)!==128||(e[t+2]&192)!==128||(e[t+3]&192)!==128||e[t]===240&&(e[t+1]&240)===128||e[t]===244&&e[t+1]>143||e[t]>244)return false;t+=4}return true}r=isValidUTF8;var t=r;var a=e;try{"default"in e&&(a=e.default)}catch(e){}var l={};try{l=a(new URL(import.meta.url.slice(0,import.meta.url.lastIndexOf("/"))).pathname)}catch(e){l=t}var i=l;export{i as default};

