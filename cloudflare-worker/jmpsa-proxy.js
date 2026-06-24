// データ提供元(www.jmpsa.or.jp) 用の CORS プロキシ (Cloudflare Worker)。
//
// Web公開時、ブラウザはデータ提供元へ直接 fetch できない(CORSヘッダーが無いため)。
// この Worker が中継し Access-Control-Allow-Origin を付けて返すことで、
// 公開Web版でもライブ取得(location.php)と詳細取得(備考/予約URL)が動くようになる。
//
// ▼ デプロイ手順(Cloudflareダッシュボード・CLI不要):
//   1. https://dash.cloudflare.com → Workers & Pages → Create application
//      → Create Worker → 名前を「motopark-proxy」等にして Deploy。
//   2. 「Edit code」でこのファイルの内容を貼り付けて Save and deploy。
//   3. 払い出される URL (例: https://motopark-proxy.<あなた>.workers.dev) を
//      Flutterの web ビルドに --dart-define=JMPSA_PROXY=<そのURL> で渡す。
//      (.github/workflows/deploy-web.yml に設定済み。URLだけ差し替える)

const UPSTREAM = 'https://www.jmpsa.or.jp';

// 許可するオリジン。末尾スラッシュは付けない(ブラウザのOriginと完全一致させるため)。
// 全公開にする場合は ['*'] にする。
// 例: GitHub Pages なら 'https://<ユーザー名>.github.io'
const ALLOW_ORIGINS = ['https://naaos.github.io'];

export default {
  async fetch(request) {
    const allowOrigin = pickAllowOrigin(request);

    // CORS プリフライト
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders(allowOrigin) });
    }
    if (request.method !== 'GET') {
      return new Response('Method Not Allowed', { status: 405, headers: corsHeaders(allowOrigin) });
    }

    const url = new URL(request.url);
    const target = UPSTREAM + url.pathname + url.search;

    let upstream;
    try {
      upstream = await fetch(target, {
        headers: { 'User-Agent': 'Mozilla/5.0 (MotoParkProxy)' },
      });
    } catch (e) {
      return new Response('Upstream fetch failed', { status: 502, headers: corsHeaders(allowOrigin) });
    }

    const headers = new Headers(corsHeaders(allowOrigin));
    // 一部エンドポイントは Content-Type が不正(末尾;)なので正規化する。
    const ct = upstream.headers.get('content-type') || '';
    if (ct.includes('text/html')) {
      headers.set('content-type', 'text/html; charset=utf-8');
    } else if (ct) {
      headers.set('content-type', ct);
    }

    return new Response(upstream.body, { status: upstream.status, headers });
  },
};

// ブラウザが送ってきた Origin を許可リストと照合し、一致すればその Origin を
// そのまま返す。これにより末尾スラッシュ等の不一致による CORS 失敗を防ぐ。
function pickAllowOrigin(request) {
  if (ALLOW_ORIGINS.includes('*')) return '*';
  const origin = request.headers.get('Origin') || '';
  const normalized = origin.replace(/\/+$/, '');
  for (const allowed of ALLOW_ORIGINS) {
    if (allowed.replace(/\/+$/, '') === normalized) return origin;
  }
  // 不一致時は先頭の許可オリジンを返す(末尾スラッシュは除去)。
  return ALLOW_ORIGINS[0].replace(/\/+$/, '');
}

function corsHeaders(allowOrigin) {
  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
}
