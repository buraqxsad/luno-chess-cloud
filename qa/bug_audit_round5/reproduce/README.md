# Yeniden çalıştırma

Pinned Flutter3.47.1/Dart3.13.1/Java21/Node22; önce /workspace/toolchains/luno-env.sh. Betikler kayıtlı worker yollarını içerir; farklı makinede yolları uyarlayın. .log/.tap/.jsonl/.patch/.diff ham içerikleri gzip’tedir; açarak kullanın. Gzip geçerli patch context baytlarını korur. Doğrulanmamış güvenlik scratch’i veya external-import proposal testleri kabul edilmiş CI testleri değildir; normal test kümesine eklemeyin. Gerçek regresyonlar kaynakta kendi portable test dosyalarındadır.

SDK yalnız exactdemo localhost namespace, fake Google/Auth ve dar in-memory transport koşulu ile çalışır; production kabulü değildir. Snapshot RAM’i park/restore betikleri sadece durmuş emulator için geçici disk içindir; RAM içeriği Git’e girmez. Manifest, kanıt byte’larını listeler.
