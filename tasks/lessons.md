# Lessons Learned — agentandbot.com

## Session: 2026-02-22

### Lesson 1: DRY — Agent Veri Tekrarı
- **Hata**: Agent verisi `marketplace_live.ex`, `agent_detail_live.ex`, `api/agent_controller.ex` içinde 3 kez tekrarlandı
- **Kural**: Shared data her zaman tek bir kaynak modülde olmalı (`GovernanceCore.Agents`)
- **Düzeltme**: Merkezi bir context modülü oluştur, LiveView ve controller'lar oradan çeksin

### Lesson 2: Verification — Port/DB Sorunlarını Çözme
- **Hata**: `mix test` ve dev server başlatılamayınca durumu sadece rapor ettik
- **Kural**: Verification engellerini otonom çöz — port bul, DB'siz test yaz, alternatif doğrulama bul
- **Düzeltme**: `mix compile --warnings-as-errors` yeterli değil, en azından unit testler çalışmalı

### Lesson 3: Stitch MCP — Config ≠ Bağlantı
- **Hata**: MCP config'e eklendi ama IDE yeniden başlatılmadığı için bağlanamadık
- **Kural**: MCP server eklendiğinde her zaman bağlantı doğrulaması yap (`list_resources`)
