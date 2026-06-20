// JMPSA(www.jmpsa.or.jp) 用の CORS プロキシ (Cloudflare Worker)。
//
// Web公開時、ブラウザは JMPSA へ直接 fetch できない(CORSヘッダーが無いため)。
// この Worker が JMPSA へ中継し Access-Control-Allow-Origin を付けて返すことで、
// 公開Web版でもライブ取得(location.php)と詳細取得(備考/予約URL)が動くようになる。
//
// ▼ デプロイ手順(Cloudflareダッシュボード・CLI不要):
//   1. https://dash.cloudflare.com → Workers & Pages → Create application
//      → Create Worker → 名前を「motopark-proxy」等にして Deploy。
//   2. 「Edit code」でこのファイルの内容を貼り付けて Save and deploy。
//   3. 払い出される URL (例: https://motopark-proxy.<あなた>.workers.dev) を
//      Flutterの web ビルドに --dart-define=JMPSA_PROXY=<そのURL> で渡す。
//      (.github/workflows/deploy-web.yml に設定済み。URLだけ差し替える)
//
// セキュリティ: 読み取り専用の公開プロキシ。ALLOW_ORIGIN を自分の
// github.io ドメインに絞るとより安全(既定は全許可)。

const UPSTREAM = 'https://www.jmpsa.or.jp';
const ALLOW_ORIGIN = '*'; // 例: 'https://<ユーザー名>.github.io' に絞ると安全

export default {
  async fetch(request) {
    // CORS プリフライト
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders() });
    }
    if (request.method !== 'GET') {
      return new Response('Method Not Allowed', { status: 405, headers: corsHeaders() });
    }

    const url = new URL(request.url);
    const target = UPSTREAM + url.pathname + url.search;

    let upstream;
    try {
      upstream = await fetch(target, {
        headers: { 'User-Agent': 'Mozilla/5.0 (MotoParkProxy)' },
      });
    } catch (e) {
      return new Response('Upstream fetch failed', { status: 502, headers: corsHeaders() });
    }

    const headers = new Headers(corsHeaders());
    // JMPSAの一部エンドポイントは Content-Type が不正(末尾;)なので正規化する。
    const ct = upstream.headers.get('content-type') || '';
    if (ct.includes('text/html')) {
      headers.set('content-type', 'text/html; charset=utf-8');
    } else if (ct) {
      headers.set('content-type', ct);
    }

    return new Response(upstream.body, { status: upstream.status, headers });
  },
};

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': ALLOW_ORIGIN,
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Max-Age': '86400',
  };
}
