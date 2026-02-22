# Projeye Katkıda Bulunma Rehberi

Bu projeye katkıda bulunduğunuz için teşekkür ederiz! Aşağıda "Yorumları İzleme" özelliği ve genel geliştirme akışı hakkında bilgiler bulabilirsiniz.

## Yorumları İzleme (Comment Monitoring)

Bu özellik, dış kaynaklardan (Twitter, YouTube vb.) gelen yorumları veya sistem mesajlarını simüle ederek gerçek zamanlı olarak arayüzde gösterir.

### Nasıl Çalışır?

1.  **Elixir Backend (`governance_core`):**
    *   `GovernanceCore.Monitoring.CommentMonitor`: Yorumları saklayan ve yayınlayan bir GenServer.
    *   `GovernanceCoreWeb.CommentController`: `/api/comments` endpointi üzerinden POST isteklerini karşılar.
    *   `GovernanceCoreWeb.AgentConnectLive`: `/agent/connect` sayfasında gelen yorumları canlı olarak listeler.

2.  **Python Script (`monitor_comments.py`):**
    *   Bu script, dış dünyadan gelen yorumları simüle eder.
    *   Rastgele yorumlar oluşturur ve `/api/comments` adresine gönderir.

### Nasıl Test Edilir?

1.  **Phoenix Sunucusunu Başlatın:**
    ```bash
    cd governance_core
    mix setup
    mix phx.server
    ```
    Sunucu `localhost:4000` adresinde çalışacaktır.

2.  **Arayüzü Açın:**
    Tarayıcınızda `http://localhost:4000/agent/connect` adresine gidin. "Live Log" bölümünü göreceksiniz.

3.  **Python Scriptini Çalıştırın:**
    Yeni bir terminal penceresinde:
    ```bash
    python3 monitor_comments.py
    ```
    Bu script çalışmaya başladığında, terminalde gönderilen mesajları göreceksiniz. Aynı anda tarayıcıdaki "Live Log" ekranında da bu mesajların belirdiğini gözlemlemelisiniz.

## Testler

Proje `ExUnit` kullanmaktadır. Testleri çalıştırmak için:

```bash
cd governance_core
mix test
```

Yeni eklenen `Monitoring` modülü için testler `test/governance_core/monitoring_test.exs` dosyasında bulunabilir.

## İletişim

Herhangi bir sorunuz varsa `agentandbot-design` ekibiyle iletişime geçebilirsiniz.
