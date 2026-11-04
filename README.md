# Embarque Ellus

Aplicativo móvel oficial da equipe de monitores da **Ellus Educação e Turismo** para gerenciamento operacional de viagens estudantis.

Desenvolvido em **Flutter** (Android e iOS) com arquitetura **offline-first**, o aplicativo permite o controle de embarque e retorno de passageiros nos ônibus via leitura de QR Code e o controle de entrada e saída de alunos nos quartos (em viagens com pernoite) por meio de **reconhecimento facial executado localmente no aparelho**.

---

## Principais Funcionalidades

- **Controle de Embarque e Retorno (QR Code)**
  - Carregamento de viagens e listas de passageiros por leitura de QR Code.
  - Marcação de embarque e retorno por ônibus, com atualização entre monitores e o painel web administrativo.
- **Controle de Quartos e Movimentação com Reconhecimento Facial**
  - Cadastro e identificação facial on-device usando **Google ML Kit** (detecção facial) + **MobileFaceNet / ArcFace (`tflite_flutter`)** para extração de embeddings de 192 dimensões.
  - Registro ágil de entrada e saída de quartos e consulta de alunos por local/quarto.
- **Operação Offline-First e Sincronização Inteligente**
  - Persistência local em **SQLite** (schema v13) com fila transacional de operações pendentes (`sync_queue`).
  - Sincronização automática em segundo plano e ao retomar o aplicativo (`AppLifecycleState.resumed`), preservando o horário real de cada evento e protegendo marcações locais contra sobrescrita.
  - Filtragem inteligente de dados: o aparelho sincroniza apenas viagens ativas ou próximas, reduzindo o consumo de dados e acelerando o reconhecimento facial.
- **Autenticação e Perfil do Monitor**
  - Login por CPF e senha integrado à API REST (JWT + Refresh Token de 30 dias) com fallback seguro para autenticação offline (SHA-256) para usuários já autenticados no dispositivo.
  - Troca obrigatória de senha provisória no primeiro acesso (`precisa_trocar_senha`) e tela **Meu Perfil** para alteração de senha a qualquer momento.

---

## Privacidade e Segurança

- **Nenhuma foto é salva ou enviada:** durante o cadastro ou reconhecimento facial, a imagem capturada pela câmera é processada exclusivamente em memória para gerar um vetor numérico (*embedding* facial de 192 dimensões), a partir do qual não é possível reconstruir a imagem original, sendo descartada imediatamente após o cálculo.
- **Acesso restrito:** uso exclusivo por colaboradores/monitores da Ellus com contas gerenciadas pelo painel administrativo web. No iOS, o app é distribuído como **App Não Listado (Unlisted App Distribution)** exclusivamente para iPhone.

---

## Stack Tecnológica

| Camada | Tecnologias |
| :--- | :--- |
| **Framework** | Flutter (Dart `>=3.0.0 <4.0.0`) |
| **Banco de Dados Local** | `sqflite` (SQLite), `shared_preferences` |
| **Visão Computacional & IA** | `tflite_flutter` (`arcface.tflite`), `google_mlkit_face_detection`, `google_mlkit_barcode_scanning`, canais nativos iOS/Android |
| **Câmera e Mídia** | `camera`, `image_picker`, `image` |
| **Rede & Autenticação** | `http`, API REST Node.js (`PainelEllus`), JWT, `crypto` (SHA-256), `connectivity_plus` |
| **Monitoramento** | `sentry_flutter` |

---

## Estrutura do Projeto

```text
embarqueellusoficial/
├── android/                  # Configurações nativas Android (Kotlin, Gradle 8.14, R8, NDK 28)
├── ios/                      # Configurações nativas iOS (Swift, UIScene lifecycle, Podfile)
├── assets/
│   ├── icon/                 # Ícones do aplicativo e splash screen
│   └── models/arcface.tflite # Modelo TFLite para extração de embeddings faciais
├── lib/
│   ├── config/               # Configurações de ambiente e endpoints da API
│   ├── constants/            # Constantes de movimentações e estados
│   ├── database/             # DatabaseHelper (SQLite v13, migrações e fila offline)
│   ├── models/               # Modelos de domínio (Passageiro, Quarto, Evento, Câmera)
│   ├── screens/              # Telas do app (Login, Menu, Perfil, Embarque, Retorno, Facial, Quartos)
│   ├── services/             # Serviços de autenticação, API, sincronização e reconhecimento facial
│   ├── widgets/              # Componentes reutilizáveis (leitor QR, ícone de status de sync)
│   └── main.dart             # Ponto de entrada e inicialização de serviços
└── pubspec.yaml              # Dependências e metadados da versão (5.2.1)
```

---

## Como Executar o Projeto

### Pré-requisitos
- **Flutter SDK** compatível com Dart 3.x
- **Android Studio** (SDK 36 / NDK 28 / JDK 17) para build Android
- **Xcode** + **CocoaPods** para build iOS

### Passo a passo

1. Acesse a pasta do aplicativo e instale as dependências:
   ```bash
   cd embarqueellusoficial
   flutter pub get
   ```

2. Certifique-se de que o arquivo `.env` está presente na raiz de `embarqueellusoficial/` com as variáveis de ambiente necessárias (URL da API backend e DSN do Sentry).

3. Execute em modo de desenvolvimento:
   ```bash
   flutter run
   ```

4. Para gerar os builds de produção:
   ```bash
   # Android (App Bundle / APK)
   flutter build appbundle --release
   flutter build apk --release

   # iOS
   flutter build ipa --release
   ```

---

## Histórico Recente de Versões

- **v5.2.1:** 14 correções de produção (sincronização automática ao retomar o app, proteção de pendências locais no SQLite v13, validação de embeddings faciais, melhorias no ciclo de vida da câmera/QR Code e refinamento do fallback de login offline).
- **v5.2.0:** Adição da tela **Meu Perfil**, alteração de senha pelo aplicativo e exigência de troca de senha no primeiro login.
- **v5.1.0:** Adoção do ciclo de vida `UIScene` para compatibilidade com o SDK do iOS 27, configuração exclusiva para iPhone e revisão das descrições de privacidade no `Info.plist`.
- **v5.0.0:** Nova fila offline de embarque, envio por operação em lotes, renovação automática de sessão por 30 dias, sincronização apenas de viagens ativas/próximas e remoção da área administrativa do app móvel (centralizada no painel web).
