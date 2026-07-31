# Quita

**Cobranças on-chain multi-moeda na Arc — com certeza antes de pagar.**

Crie uma cobrança em USDC ou EURC, compartilhe um link ou QR Code, e receba direto na sua carteira. O pagador vê **antes de gastar gás** se o pagamento vai passar.

🔗 **App:** https://quitapay.xyz
📜 **Contrato:** [`0xF1979d37646266f3C5C2c250F0F8798D6E0f28D7`](https://testnet.arcscan.app/address/0xF1979d37646266f3C5C2c250F0F8798D6E0f28D7) — verificado (Sourcify, Exact Match)
🌐 **Rede:** Arc Testnet (Chain ID `5042002`)

---

## O diferencial: `podePagar`

A maioria dos apps de pagamento deixa a transação falhar na cara do usuário. Ele assina, gasta gás, e só então descobre que faltava saldo ou aprovação.

O Quita pergunta ao contrato **antes**:

```solidity
function podePagar(uint256 id, address pagador)
    external view returns (bool ok, string memory motivo)
```

A resposta vira um semáforo na interface:

| Estado | Significado |
|---|---|
| 🟢 **Pronto para pagar** | Saldo e aprovação conferidos — é só confirmar |
| 🟡 **Falta aprovar o token** | Tem saldo, mas precisa liberar o token uma vez |
| 🔴 **Motivo específico** | Saldo insuficiente, cobrança já paga, cancelada, ou é sua |

O usuário resolve o problema **antes** de gastar gás. Nenhuma transação falha à toa.

---

## Como funciona

1. **Você cria** uma cobrança: valor, moeda (USDC/EURC) e descrição
2. **O app gera** um link compartilhável (`?id=N`) e um QR Code
3. **O pagador abre**, vê o semáforo, aprova o token e paga
4. **A liquidação é instantânea** — o valor vai direto do pagador para você

### O contrato nunca guarda dinheiro

O `transferFrom` move o valor do pagador para o recebedor **na mesma transação**. O contrato não tem saldo em momento algum — não existe o que roubar, e não existe função de saque.

### Memo on-chain

Cada pagamento pode carregar uma mensagem de até 140 caracteres, gravada permanentemente na blockchain junto com a transação. Útil para número de nota fiscal, referência de pedido, ou qualquer identificação que precise ser auditável.

---

## Interface

- 🌍 **4 idiomas** — Português, Inglês, Espanhol e Francês
- 📱 **QR Code** gerado para cada cobrança
- 🔗 **Hash da transação** com link para o explorer em toda operação
- 📊 **Histórico** de cobranças emitidas e pagas
- ⚡ **Zero dependências externas** — bibliotecas embutidas, funciona offline após carregar

---

## Contrato

### Funções de escrita

| Função | O que faz |
|---|---|
| `criarCobranca(valor, moeda, descricao)` | Cria a cobrança e devolve o ID |
| `pagar(id, memo)` | Paga (exige `approve` antes) |
| `cancelar(id)` | Cancela — só o recebedor, só se ainda aberta |

### Funções de leitura

| Função | O que devolve |
|---|---|
| `podePagar(id, pagador)` | `(bool ok, string motivo)` — a checagem prévia |
| `consultar(id)` | A cobrança inteira |
| `cobrancasEmitidas(endereco)` | IDs criados por um endereço |
| `cobrancasPagas(endereco)` | IDs pagos por um endereço |
| `totalCobrancas()` | Total já criado |
| `enderecoDoToken(moeda)` | Endereço do token (0 = USDC, 1 = EURC) |

### Eventos

`CobrancaCriada` · `CobrancaPaga` · `CobrancaCancelada`

### Endereços dos tokens (Arc Testnet)

| Token | Endereço | Decimais |
|---|---|---|
| USDC | `0x3600000000000000000000000000000000000000` | 6 |
| EURC | `0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a` | 6 |

> Na Arc, o USDC nativo (gás) usa 18 decimais, mas a interface ERC-20 usa 6. O Quita usa **exclusivamente a interface ERC-20**, conforme recomenda a documentação da Circle. Um único caminho de código, ambas as moedas com 6 decimais.

### Valores em 6 decimais

| Você quer cobrar | Valor no contrato |
|---|---|
| 1 USDC | `1000000` |
| 10,50 USDC | `10500000` |
| 0,25 USDC | `250000` |
| 100 EURC | `100000000` |

---

## Decisões de projeto

**Zero imports.** A interface ERC-20 e a proteção contra reentrância estão escritas dentro do próprio arquivo. Sem OpenZeppelin, sem dependência externa — a verificação "single file" no explorer sempre funciona.

**Versão do compilador fixa.** `pragma solidity 0.8.20;` sem o acento circunflexo. Não existe ambiguidade sobre qual compilador reproduz o bytecode.

**Sem constructor.** Os endereços dos tokens são constantes no código. Resultado: zero argumentos na verificação, que é onde a maioria das verificações falha.

**Checks-effects-interactions.** O estado da cobrança muda para "Paga" **antes** da transferência, e um modificador de reentrância protege a função. Padrão de segurança aplicado mesmo sem o contrato custodiar fundos.

---

## Detalhes do deploy

```
Contrato:    Quita
Endereço:    0xF1979d37646266f3C5C2c250F0F8798D6E0f28D7
Rede:        Arc Testnet (Chain ID 5042002)
Compilador:  0.8.20+commit.a1b79de6
Otimização:  Ativada, 200 runs
Bloco:       53519198
Verificação: Sourcify — Exact Match (runtime + creation bytecode)
```

---

## Rodando localmente

O app é **um único arquivo HTML** sem build, sem npm, sem servidor. Baixe o `index.html` e abra no navegador.

⚠️ Para conectar a carteira, é preciso servir por **HTTP/HTTPS**. Abrir o arquivo direto do disco (`file://`) não funciona: carteiras não reconhecem arquivos locais como dapp.

### Configuração da rede

| Campo | Valor |
|---|---|
| Nome | Arc Testnet |
| RPC | `https://rpc.testnet.arc.network` |
| Chain ID | `5042002` |
| Moeda | USDC |
| Explorer | `https://testnet.arcscan.app` |

Tokens de teste: [faucet.circle.com](https://faucet.circle.com) — selecione **Arc Testnet** e peça USDC e EURC.

---

## Status

Testado em produção na Arc Testnet: criação, aprovação, pagamento com liquidação real entre carteiras distintas, e cancelamento. Todas as funções do contrato exercitadas on-chain.

**Este é um projeto em testnet.** Não use com fundos reais.

---

## Licença

MIT
