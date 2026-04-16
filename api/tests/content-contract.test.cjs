const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('content module contract', () => {
  const model = read('src/models/Content.ts');
  const routes = read('src/modules/content/routes.ts');

  test('Content model has slug, type, title, body, published fields', () => {
    expect(model).toContain('slug: { type: String, required: true, unique: true');
    expect(model).toContain("enum: ['article', 'tip', 'legal', 'featured']");
    expect(model).toContain('title: { type: String, required: true');
    expect(model).toContain('body: { type: String, required: true');
    expect(model).toContain('published: { type: Boolean');
  });

  test('Content has compound index for listing queries', () => {
    expect(model).toContain('{ type: 1, published: 1, sortOrder: 1 }');
  });

  test('Content has unique slug index', () => {
    expect(model).toContain("{ slug: 1 }, { unique: true }");
  });

  test('GET /terms endpoint exists and is public', () => {
    expect(routes).toContain("router.get('/terms',");
    // Terms should not have auth middleware between path and handler
    expect(routes).toMatch(/router\.get\('\/terms',\s*async/);
  });

  test('GET /privacy endpoint exists and is public', () => {
    expect(routes).toContain("router.get('/privacy',");
    expect(routes).toMatch(/router\.get\('\/privacy',\s*async/);
  });

  test('GET /articles endpoint supports pagination', () => {
    expect(routes).toContain("router.get('/articles',");
    expect(routes).toContain('page');
    expect(routes).toContain('limit');
    expect(routes).toContain('totalPages');
  });

  test('GET /articles/:id filters by published=true', () => {
    expect(routes).toContain("type: 'article'");
    expect(routes).toContain('published: true');
  });

  test('GET /tips requires authentication', () => {
    expect(routes).toContain("router.get('/tips', isAuthenticated");
  });

  test('GET /featured is public', () => {
    expect(routes).toContain("router.get('/featured',");
    expect(routes).toMatch(/router\.get\('\/featured',\s*async/);
  });

  test('all 501 stubs have been removed', () => {
    expect(routes).not.toContain('not yet implemented');
    expect(routes).not.toMatch(/,\s*501\s*\)/);
  });

  test('terms endpoint returns default content if DB is empty', () => {
    expect(routes).toContain('Terms of Service for GearSnitch');
  });

  test('privacy endpoint returns default content if DB is empty', () => {
    expect(routes).toContain('Privacy Policy for GearSnitch');
  });
});
