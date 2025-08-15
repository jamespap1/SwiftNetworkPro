// GitHub'da F12 açıp Console'a yapıştırın ve çalıştırın
console.log("=== GITHUB ANCHOR DEBUG ===");

// Tüm h1, h2, h3 başlıklarını bul
const headers = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
headers.forEach((header, index) => {
    const text = header.textContent.trim();
    const id = header.id || 'NO-ID';
    const anchor = header.querySelector('a.anchor');
    const href = anchor ? anchor.getAttribute('href') : 'NO-HREF';
    
    console.log(`${index + 1}. "${text}"`);
    console.log(`   ID: "${id}"`);
    console.log(`   HREF: "${href}"`);
    console.log(`   TAG: ${header.tagName}`);
    console.log('---');
});

// user-content prefix'li ID'leri de kontrol et
console.log("\n=== USER-CONTENT IDs ===");
const userContentElements = document.querySelectorAll('[id^="user-content-"]');
userContentElements.forEach((el, index) => {
    console.log(`${index + 1}. ID: "${el.id}" -> Text: "${el.textContent?.trim() || 'NO-TEXT'}"`);
});

console.log("\n=== ANCHOR LINKS ===");
const anchorLinks = document.querySelectorAll('a.anchor');
anchorLinks.forEach((link, index) => {
    const href = link.getAttribute('href');
    const parent = link.closest('h1, h2, h3, h4, h5, h6');
    const text = parent ? parent.textContent.trim() : 'NO-PARENT';
    console.log(`${index + 1}. "${text}" -> "${href}"`);
});