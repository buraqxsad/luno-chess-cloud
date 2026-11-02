# İkinci turda kapatılan altı yeni kusur

1 P1 + 5 P2. Önceki yedi düzeltme yeniden sayılmadı. Aynı fix içindeki retry/ownership alt senaryoları ayrı bug diye şişirilmedi.

| Önem | Hata | Commit | Kök neden / düzeltme | Kanıt |
| --- | --- | --- | --- | --- |
| P1 | Owned inactive subscription restore | `162dfbb` | Güncel ON_HOLD/EXPIRED Google kararı eski claim/profile hakkına uygulanmıyordu. Owner/product doğrulaması, claim CAS ve profile projection ile sadece owned token güncellenir; diğer aktif token ve yeni renewal korunur. | [Alan raporu](areas/economy/REPORT.md) |
| P2 | Billing snapshot sırası | `ca16acf` | Eski restore, yeni verification snapshot’ını ezip ikinci üyelik launch’ını açabiliyordu. Revision/observedAt ve legacy fallback sırası korunur; session reset ve bozuk metadata denetlenir. | [Alan raporu](areas/client/REPORT.md) |
| P2 | Covered Friendly route | `3df9d16` | Geç join yanıtı ilgisiz üst route’u replace ediyordu. Match pending tutulur; owner route current/resumed olunca bir kez açılır; account/dispose eski callback’i keser. | [Alan raporu](areas/client/REPORT.md) |
| P2 | Silme sonrası V1 admission | `3936314` | HTTP403 eski queue/room private metadata’sını temizlemiyordu. Existing account-metadata pre/post gate ve leaveAccount cleanup iki canonical admission route’a uygulanır. | [Alan raporu](areas/online/REPORT.md) |
| P2 | DM moderation membership | `dbbfbc2` | Legacy conversation-key collision başka pair’in mesajını moderation’a kopyalayabiliyordu. Declared exact pair kontrolü yalnız bounded members + seçilmiş message read ile yapılır; eski members-absent contract korunur. | [Alan raporu](areas/security/REPORT.md) |
| P2 | Authored notification erasure | `9d41c50` | Push-ID ve reddedilmiş/orphan ilişki notices’ında silinen UID/alias kalıyordu. Bounded recipient pagination, owner-aware removal, retry checkpoint ve ayrı bounded private resume limiter eklenir; Authfailure counter’ı finalcleanup’a kadar saklanır. | [Alan raporu](areas/security/REPORT.md) |

Her hata için başarısız tekrar üretim ve sonra geçen regresyon kaydedildi. Online ajanının dört ek test yazma/çalıştırma çağrısı otomatik incelemede kullanım limitinde reddedildi ve çalışmadı. Root daha dar mevcut altı vakayı kaynak mutasyonu/izin yükseltmesi olmadan 6/6 doğruladı; yazılmayan dört test PASS sayılmadı.
