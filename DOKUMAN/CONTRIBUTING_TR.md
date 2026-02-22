# Projeye Katkıda Bulunma Rehberi

## ClawHub Skill Monitor

Bu özellik, `clawhub.ai` üzerinde yeni bir yetenek (skill) oluşturulduğunda veya güncellendiğinde, sistemimizin bunu algılamasını ve arayüzde göstermesini sağlar.

### Kurulum

1.  **Backend Başlat:**
    ```bash
    cd governance_core
    mix setup
    mix phx.server
    ```

2.  **Monitor Scriptini Çalıştır:**
    ```bash
    python3 monitor_clawhub.py
    ```
    Bu script, sağlanan API Token (`clh_...`) ile ClawHub'ı izler (simülasyon).

3.  **İzle:**
    `http://localhost:4000/agent/connect` adresinde "ClawHub" etiketli turuncu uyarıları göreceksiniz.

### Test

```bash
cd governance_core
mix test
```
