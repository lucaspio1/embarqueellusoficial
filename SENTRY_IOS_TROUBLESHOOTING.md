# Troubleshooting: Sentry não envia logs no iOS

## Problema

O Sentry funciona perfeitamente no **Android**, mas **não recebe logs** no **iOS**, mesmo após instalação correta do CocoaPods.

## Verificações Realizadas

✅ Dependência `sentry_flutter: ^8.15.0` instalada
✅ Pod instalado: `Sentry (8.56.2)` e `sentry_flutter (9.8.0)`
✅ Código Dart com inicialização correta do Sentry
✅ DSN configurado corretamente

## Possíveis Causas e Soluções

### 1. **Modo Debug vs Release no iOS**

O Sentry pode não funcionar corretamente em modo **Debug** no iOS. Por padrão, o Flutter compila em Debug quando você usa `flutter run`.

**Solução:**
```bash
# Teste em modo Release no simulador
flutter run --release

# Ou em modo Profile (recomendado para testes)
flutter run --profile
```

### 2. **Verificar se o Sentry está realmente inicializando**

Adicione logs para confirmar que o Sentry está inicializando corretamente:

```dart
Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://16c773f79c6fc2a3a4951733ce3570ed@o4504103203045376.ingest.us.sentry.io/4510326779740160';
      options.tracesSampleRate = 1.0;
      options.debug = true;  // ← Já habilitado
      options.environment = 'production';

      // Adicione este callback para confirmar inicialização
      print('🔵 Sentry DSN configurado: ${options.dsn}');
    },
    appRunner: () async {
      print('🔵 Sentry inicializado - iniciando app');
      // ... resto do código
    },
  );
}
```

**Verificação:** Procure nos logs do Xcode/Console por mensagens do Sentry como:
- `Sentry DSN configurado: https://...`
- `Sentry initialized`

### 3. **Testar envio manual de evento**

Adicione um teste manual para verificar se o Sentry está funcionando:

```dart
// Adicione no initState() de alguma tela ou no main.dart após inicialização
Future.delayed(Duration(seconds: 5), () async {
  print('📤 Enviando evento de teste para Sentry...');
  await Sentry.captureMessage(
    'TESTE MANUAL - iOS Sentry está funcionando!',
    level: SentryLevel.info,
  );
  print('📤 Evento de teste enviado');
});
```

### 4. **Verificar conectividade de rede no iOS**

O iOS pode bloquear requisições de rede em desenvolvimento. Verifique:

**a) Info.plist - Permitir HTTP (se necessário):**

Adicione em `ios/Runner/Info.plist` (apenas se Sentry usar HTTP em dev):

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

⚠️ **Atenção:** Isso é apenas para desenvolvimento. Remova antes de publicar.

**b) Verificar se o simulador/dispositivo tem internet:**
```bash
# No terminal do Mac
ping sentry.io
```

### 5. **Limpar cache do CocoaPods e recompilar**

Às vezes o cache do CocoaPods pode causar problemas:

```bash
cd ios
rm -rf Pods Podfile.lock
pod cache clean --all
pod install --repo-update
cd ..
flutter clean
flutter pub get
flutter run --release  # Teste em release
```

### 6. **Verificar configurações do Xcode**

**a) Abra o projeto no Xcode:**
```bash
cd ios
open Runner.xcworkspace  # NÃO use Runner.xcodeproj
```

**b) Verifique Build Settings:**
- Target: **Runner**
- Build Settings → Search "Bitcode"
  - **Enable Bitcode: NO** (Sentry não funciona com Bitcode habilitado)

**c) Verifique se não há erros de build:**
- Product → Clean Build Folder (Cmd+Shift+K)
- Product → Build (Cmd+B)

### 7. **Verificar permissões de rede no iOS 14+**

Se estiver usando iOS 14 ou superior, pode precisar da permissão de tracking:

Em `ios/Runner/Info.plist`, adicione:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>Este aplicativo envia dados de erro para melhorar a experiência do usuário.</string>
```

### 8. **Testar com evento de erro real**

Adicione um botão de teste na UI para forçar um erro:

```dart
ElevatedButton(
  onPressed: () async {
    try {
      throw Exception('TESTE SENTRY iOS - Erro forçado');
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      print('📤 Exceção enviada para Sentry');
    }
  },
  child: Text('Testar Sentry'),
)
```

### 9. **Verificar logs do Sentry no Xcode Console**

**a) Com debug habilitado (`options.debug = true`), você deve ver:**

```
[Sentry] [debug] Starting SDK...
[Sentry] [debug] Installed integration: ...
[Sentry] [debug] Successfully sent event ...
```

**b) Se você ver erros como:**

```
[Sentry] [error] Failed to send event: ...
```

Isso indica problema de conectividade ou configuração.

### 10. **Configurar Upload de Debug Symbols (opcional)**

Para rastreamento completo de crashes nativos, adicione script de upload:

**a) No Xcode:**
1. Selecione **Runner** → **Build Phases**
2. Clique em **+** → **New Run Script Phase**
3. Adicione o script:

```bash
export SENTRY_PROPERTIES=sentry.properties
/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/sentry_upload_debug_symbols.sh"
```

**b) Crie `ios/sentry.properties`:**

```properties
defaults.url=https://sentry.io/
defaults.org=seu-org
defaults.project=seu-projeto
auth.token=SEU_AUTH_TOKEN
```

## Checklist de Diagnóstico

Execute cada item e marque:

- [ ] 1. Testou em modo **Release** ou **Profile**?
- [ ] 2. Viu mensagens de inicialização do Sentry nos logs?
- [ ] 3. Testou envio manual de evento com `Sentry.captureMessage()`?
- [ ] 4. Verificou conectividade de rede (ping sentry.io)?
- [ ] 5. Limpou cache do CocoaPods e recompilou?
- [ ] 6. Verificou Build Settings no Xcode (Bitcode desabilitado)?
- [ ] 7. Adicionou permissão de tracking no Info.plist?
- [ ] 8. Verificou logs do Sentry no Xcode Console?
- [ ] 9. Testou com erro real (try/catch)?
- [ ] 10. Abriu o dashboard do Sentry para ver se há eventos?

## Dashboard do Sentry

Acesse: https://sentry.io/organizations/seu-org/issues/

Filtros úteis:
- **Platform: iOS** (vs Android)
- **Environment: production**
- **Last 24 hours**

## Comparação Android vs iOS

| Item | Android | iOS |
|------|---------|-----|
| Funciona em Debug? | ✅ Sim | ⚠️ Pode não funcionar |
| Precisa Release? | ❌ Não | ✅ Recomendado |
| Bitcode | N/A | ❌ Deve estar desabilitado |
| Debug Symbols | Automático | Precisa script |

## Próximos Passos

1. **Execute o checklist acima**
2. **Teste em modo Release:**
   ```bash
   flutter run --release
   ```
3. **Adicione teste manual** (botão de teste)
4. **Verifique logs do Xcode Console** (`options.debug = true`)
5. **Acesse dashboard do Sentry** para confirmar recebimento

## Suporte

Se o problema persistir após todas as verificações:

1. Verifique se o DSN está correto
2. Confirme que o projeto Sentry existe e está ativo
3. Teste com DSN de outro projeto Sentry (criar novo projeto de teste)
4. Abra issue no GitHub do sentry-flutter: https://github.com/getsentry/sentry-dart/issues

---

**Última atualização:** $(date +%Y-%m-%d)
