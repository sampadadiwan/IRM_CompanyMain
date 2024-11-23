import*as a from"node-gyp-build";var t={};
/**
 * Masks a buffer using the given mask.
 *
 * @param {Buffer} source The buffer to mask
 * @param {Buffer} mask The mask to use
 * @param {Buffer} output The buffer where to store the result
 * @param {Number} offset The offset at which to start writing
 * @param {Number} length The number of bytes to mask.
 * @public
 */const mask$1=(a,t,r,e,n)=>{for(var o=0;o<n;o++)r[e+o]=a[o]^t[3&o]};
/**
 * Unmasks a buffer using the given mask.
 *
 * @param {Buffer} buffer The buffer to unmask
 * @param {Buffer} mask The mask to use
 * @public
 */const unmask$1=(a,t)=>{const r=a.length;for(var e=0;e<r;e++)a[e]^=t[3&e]};t={mask:mask$1,unmask:unmask$1};var r=t;var e="default"in a?a.default:a;var n={};try{n=e(new URL(import.meta.url.slice(0,import.meta.url.lastIndexOf("/"))).pathname)}catch(a){n=r}var o=n;const s=n.mask,m=n.unmask;export{o as default,s as mask,m as unmask};

