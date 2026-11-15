#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { s3Request, sha256 } = require('./r2_client.js');

// 1. Load deployment environment
function loadEnvDeploy() {
  const envPath = path.join(__dirname, '..', '.env.deploy');
  if (!fs.existsSync(envPath)) {
    console.error('❌ ملف الإعدادات .env.deploy غير موجود! يرجى إنشاؤه بناءً على .env.deploy.example');
    process.exit(1);
  }

  const env = {};
  const content = fs.readFileSync(envPath, 'utf8');
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx !== -1) {
      const k = trimmed.substring(0, eqIdx).trim();
      const v = trimmed.substring(eqIdx + 1).trim();
      env[k] = v;
    }
  }
  return env;
}

// Helper to ask question in terminal
function ask(rl, query) {
  return new Promise((resolve) => rl.question(query, resolve));
}

// Main execution
async function main() {
  console.log('\n======================================================');
  console.log('🎙️  أداة رفع أذان جديد وتحديث الكتالوج السحابي (Cloudflare R2)');
  console.log('======================================================\n');

  const env = loadEnvDeploy();
  const accountId = env.R2_ACCOUNT_ID;
  const accessKeyId = env.R2_ACCESS_KEY_ID;
  const secretAccessKey = env.R2_SECRET_ACCESS_KEY;
  const bucket = env.R2_BUCKET_NAME || 'hafez-alahd';
  const catalogKey = env.R2_CATALOG_KEY || 'catalog/catalog.json';
  const audioPrefix = env.R2_AUDIO_PREFIX || 'catalog/audio/';

  // Parse CLI args or prompt interactively
  const args = process.argv.slice(2);
  let filePath = '';
  let sheikhName = '';
  let displayName = '';
  let audioType = 'general';
  let description = '';
  let durationSeconds = 0;
  let iqamaFilePath = '';
  let iqamaDurationSeconds = 0;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--file') filePath = args[++i];
    else if (args[i] === '--sheikh') sheikhName = args[++i];
    else if (args[i] === '--name') displayName = args[++i];
    else if (args[i] === '--type') audioType = args[++i];
    else if (args[i] === '--desc') description = args[++i];
    else if (args[i] === '--duration') durationSeconds = parseInt(args[++i], 10);
    else if (args[i] === '--iqama-file') iqamaFilePath = args[++i];
    else if (args[i] === '--iqama-duration') iqamaDurationSeconds = parseInt(args[++i], 10);
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  try {
    if (!filePath) {
      filePath = (await ask(rl, '📁 مسار ملف الصوت (اسحب الملف هنا أو اكتب مساره): ')).trim().replace(/['"]/g, '');
    }

    if (!fs.existsSync(filePath)) {
      console.error(`❌ الملف غير موجود في المسار: ${filePath}`);
      process.exit(1);
    }

    if (!sheikhName) {
      sheikhName = (await ask(rl, '👤 اسم الشيخ / المؤذن (مثال: الشيخ مشاري راشد العفاسي): ')).trim();
      if (!sheikhName) sheikhName = 'الشيخ مشاري راشد العفاسي';
    }

    if (!displayName) {
      displayName = (await ask(rl, `🏷️  اسم العرض (اضغط Enter للافتراضي: أذان - ${sheikhName}): `)).trim();
      if (!displayName) displayName = `أذان - ${sheikhName}`;
    }

    if (!args.includes('--type')) {
      console.log('\nنوع الأذان:');
      console.log('  1. عام (general) — لجميع الصلوات (ظهر، عصر، مغرب، عشاء)');
      console.log('  2. فجر (fajr) — يحتوي على الصلاة خير من النوم');
      console.log('  3. إقامة (iqama) — إقامة الصلاة');
      const typeChoice = (await ask(rl, 'اختر الرقم [1/2/3] (الافتراضي 1): ')).trim();
      if (typeChoice === '2') audioType = 'fajr';
      else if (typeChoice === '3') audioType = 'iqama';
      else audioType = 'general';
    }

    if (!durationSeconds) {
      const durStr = (await ask(rl, '⏱️  مدة الصوت بالثواني (مثال: 75) [اضغط Enter إذا لم تكن متأكداً]: ')).trim();
      durationSeconds = parseInt(durStr, 10) || 75;
    }

    if (!description && !args.includes('--desc')) {
      description = (await ask(rl, '📝 وصف مختصر (اختياري - اضغط Enter للتخطي): ')).trim();
    }

    if (audioType === 'general' && !iqamaFilePath) {
      const hasIqama = (await ask(rl, '\n🕌 هل يتوفر ملف صوت إقامة لهذا الأذان العام؟ [y/N]: ')).trim().toLowerCase();
      if (hasIqama === 'y' || hasIqama === 'yes' || hasIqama === 'نعم') {
        iqamaFilePath = (await ask(rl, '📁 مسار ملف صوت الإقامة (اسحب الملف هنا أو اكتب مساره): ')).trim().replace(/['"]/g, '');
        if (!fs.existsSync(iqamaFilePath)) {
          console.warn(`⚠️ ملف الإقامة غير موجود في المسار: ${iqamaFilePath}، سيتم المتابعة بدون إقامة.`);
          iqamaFilePath = '';
        } else {
          const iqDurStr = (await ask(rl, '⏱️  مدة صوت الإقامة بالثواني (الافتراضي: 25): ')).trim();
          iqamaDurationSeconds = parseInt(iqDurStr, 10) || 25;
        }
      }
    }
  } finally {
    rl.close();
  }

  // 2. Read and analyze audio file
  console.log('\n⏳ جاري قراءة الملف وحساب الحجم والبصمة الرقمية (SHA-256)...');
  const fileBytes = fs.readFileSync(filePath);
  const fileSizeBytes = fileBytes.length;
  const fileSha256 = sha256(fileBytes);
  const rawFileName = path.basename(filePath);
  const ext = path.extname(rawFileName).toLowerCase() || '.mp3';

  // Slugify ID
  const cleanSheikh = sheikhName
    .replace(/[^\w\s\u0600-\u06FF]/gi, '')
    .trim()
    .replace(/\s+/g, '_');
  const id = `remote:${cleanSheikh}_${audioType}_${Date.now().toString(36)}`;
  const targetFileName = `${cleanSheikh}_${audioType}_${fileSha256.substring(0, 16)}${ext}`;
  const objectKey = `${audioPrefix}${targetFileName}`;

  console.log(`✅ الحجم: ${(fileSizeBytes / (1024 * 1024)).toFixed(2)} ميجابايت (${fileSizeBytes} بايت)`);
  console.log(`✅ SHA-256: ${fileSha256}`);
  console.log(`✅ المعرف: ${id}`);
  console.log(`✅ مسار الرفع في R2: ${objectKey}`);

  // 3. Upload Audio File
  console.log('\n🚀 جاري رفع ملف الصوت إلى Cloudflare R2...');
  const audioUploadRes = await s3Request({
    accountId,
    bucket,
    key: objectKey,
    method: 'PUT',
    body: fileBytes,
    contentType: ext === '.wav' ? 'audio/wav' : ext === '.m4a' ? 'audio/mp4' : 'audio/mpeg',
    accessKeyId,
    secretAccessKey,
  });

  if (audioUploadRes.status !== 200 && audioUploadRes.status !== 201) {
    const errText = await audioUploadRes.text();
    console.error(`❌ فشل رفع ملف الصوت (كود ${audioUploadRes.status}):`, errText);
    process.exit(1);
  }
  console.log('✅ تم رفع ملف الصوت بنجاح!');

  // 3b. Upload Companion Iqama File if present
  let iqamaInfo = null;
  if (iqamaFilePath && fs.existsSync(iqamaFilePath)) {
    console.log('\n⏳ جاري قراءة ملف الإقامة وحساب الحجم والبصمة الرقمية (SHA-256)...');
    const iqBytes = fs.readFileSync(iqamaFilePath);
    const iqSizeBytes = iqBytes.length;
    const iqSha256 = sha256(iqBytes);
    const rawIqFileName = path.basename(iqamaFilePath);
    const iqExt = path.extname(rawIqFileName).toLowerCase() || '.mp3';
    const iqTargetFileName = `${cleanSheikh}_iqama_${iqSha256.substring(0, 16)}${iqExt}`;
    const iqObjectKey = `${audioPrefix}${iqTargetFileName}`;

    console.log(`✅ حجم الإقامة: ${(iqSizeBytes / (1024 * 1024)).toFixed(2)} ميجابايت (${iqSizeBytes} بايت)`);
    console.log(`✅ SHA-256 للإقامة: ${iqSha256}`);
    console.log(`✅ مسار رفع الإقامة في R2: ${iqObjectKey}`);

    console.log('\n🚀 جاري رفع ملف صوت الإقامة إلى Cloudflare R2...');
    const iqUploadRes = await s3Request({
      accountId,
      bucket,
      key: iqObjectKey,
      method: 'PUT',
      body: iqBytes,
      contentType: iqExt === '.wav' ? 'audio/wav' : iqExt === '.m4a' ? 'audio/mp4' : 'audio/mpeg',
      accessKeyId,
      secretAccessKey,
    });

    if (iqUploadRes.status !== 200 && iqUploadRes.status !== 201) {
      const errText = await iqUploadRes.text();
      console.error(`❌ فشل رفع ملف الإقامة (كود ${iqUploadRes.status}):`, errText);
      process.exit(1);
    }
    console.log('✅ تم رفع ملف صوت الإقامة بنجاح!');

    iqamaInfo = {
      object_key: iqObjectKey,
      file_size_bytes: iqSizeBytes,
      sha256: iqSha256,
      duration_seconds: iqamaDurationSeconds,
    };
  }

  // 4. Fetch Current Catalog JSON
  console.log('\n📥 جاري جلب ملف الكتالوج الحالي لتحديثه...');
  let catalog = {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    entries: [],
  };

  const getCatRes = await s3Request({
    accountId,
    bucket,
    key: catalogKey,
    method: 'GET',
    accessKeyId,
    secretAccessKey,
  });

  if (getCatRes.status === 200) {
    try {
      const rawCat = JSON.parse(await getCatRes.text());
      if (rawCat.schema_version === 1 && Array.isArray(rawCat.entries)) {
        catalog = rawCat;
      } else {
        console.log('ℹ️  تنسيق الكتالوج الحالي قديم، سيتم ترقيته إلى Schema v1 المعتمدة.');
      }
    } catch (_) {
      console.log('ℹ️  تعذر قراءة الكتالوج الحالي كـ JSON، سيتم إنشاء كتالوج جديد.');
    }
  } else {
    console.log('ℹ️  ملف الكتالوج غير موجود بعد، سيتم إنشاؤه لأول مرة.');
  }

  // 5. Append or Update Entry
  const newEntry = {
    id,
    sheikh_name: sheikhName,
    audio_type: audioType,
    display_name: displayName,
    description: description || undefined,
    duration_seconds: durationSeconds,
    object_key: objectKey,
    file_size_bytes: fileSizeBytes,
    sha256: fileSha256,
    preview_offset_seconds: 0,
    if_iqama: iqamaInfo || undefined,
  };
  if (iqamaInfo) {
    newEntry.iqama = iqamaInfo;
  }
  delete newEntry.if_iqama;

  // Filter out any invalid placeholder entries (must be valid 64-hex SHA-256) and remove duplicate ID
  catalog.entries = catalog.entries.filter((e) => /^[0-9a-f]{64}$/i.test(e.sha256) && e.id !== id);
  catalog.entries.push(newEntry);
  catalog.generated_at = new Date().toISOString();

  // 6. Upload Updated Catalog JSON
  console.log(`\n📤 جاري حفظ ورفع الكتالوج المحدث (${catalog.entries.length} عناصر)...`);
  const catalogJsonStr = JSON.stringify(catalog, null, 2);
  const putCatRes = await s3Request({
    accountId,
    bucket,
    key: catalogKey,
    method: 'PUT',
    body: Buffer.from(catalogJsonStr, 'utf8'),
    contentType: 'application/json; charset=utf-8',
    accessKeyId,
    secretAccessKey,
  });

  if (putCatRes.status !== 200 && putCatRes.status !== 201) {
    const errText = await putCatRes.text();
    console.error(`❌ فشل رفع ملف الكتالوج (كود ${putCatRes.status}):`, errText);
    process.exit(1);
  }

  console.log('\n======================================================');
  console.log('🎉 اكتملت العملية بنجاح تام!');
  console.log(`✅ تم رفع الصوت: ${objectKey}`);
  console.log(`✅ تم تحديث الكتالوج: ${catalogKey}`);
  console.log(`✅ إجمالي الأصوات المتاحة الآن: ${catalog.entries.length}`);
  console.log('======================================================\n');
  console.log('💡 الآن افتح تطبيق "حافظ العهد" واضغط "إعادة المحاولة" لترى الصوت الجديد فوراً!\n');
}

main().catch((err) => {
  console.error('\n❌ خطأ غير متوقع:', err);
  process.exit(1);
});
