// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * ============================================================================
 *  QUITA - Cobrancas on-chain multi-moeda na Arc
 * ============================================================================
 *
 *  O QUE FAZ:
 *  Voce cria uma cobranca (valor, descricao, moeda). Gera um link.
 *  A pessoa abre o link e paga em USDC ou EURC. O dinheiro vai DIRETO
 *  do bolso do pagador pro seu bolso, na mesma transacao.
 *
 *  O CONTRATO NUNCA GUARDA DINHEIRO.
 *  Isso elimina uma classe inteira de riscos (nao ha o que roubar aqui)
 *  e combina com a proposta de liquidacao instantanea da Arc.
 *
 *  ---------------------------------------------------------------------------
 *  DECISOES DE PROJETO (leia antes de mexer em qualquer linha)
 *  ---------------------------------------------------------------------------
 *
 *  1) ZERO IMPORTS
 *     Nao usa OpenZeppelin. A interface ERC-20 e a protecao contra
 *     reentrancia estao escritas aqui dentro. Motivo: a verificacao
 *     "Single file" no arcscan SEMPRE funciona quando nao existe
 *     dependencia externa.
 *
 *  2) VERSAO DO COMPILADOR FIXA
 *     "pragma solidity 0.8.20;" - sem o acento circunflexo (^).
 *     Nao existe ambiguidade sobre qual compilador usar na verificacao.
 *
 *  3) SEM CONSTRUCTOR
 *     Os enderecos do USDC e do EURC estao gravados como constantes.
 *     Resultado: ZERO argumentos para informar na verificacao.
 *     Esse foi exatamente o ponto onde nos perdemos antes.
 *
 *  4) TUDO EM 6 DECIMAIS
 *     Na Arc, o USDC nativo (gas) usa 18 decimais, mas a interface
 *     ERC-20 usa 6. A propria documentacao da Circle recomenda usar
 *     SOMENTE a interface ERC-20 para saldos e transferencias.
 *     Este contrato segue isso: um unico caminho de codigo, as duas
 *     moedas com 6 decimais.
 *     => 1 USDC = 1000000 | 10.50 USDC = 10500000
 *
 *  ---------------------------------------------------------------------------
 *  REDE: Arc Mainnet  |  Chain ID: 5042
 *  RPC:  https://rpc.mainnet.arc.io
 *  Explorer: https://explorer.arc.io
 *  ---------------------------------------------------------------------------
 */

/// @dev Interface ERC-20 minima. Escrita aqui dentro de proposito (ver decisao 1).
interface IERC20 {
    function transferFrom(address de, address para, uint256 valor) external returns (bool);
    function balanceOf(address dono) external view returns (uint256);
    function allowance(address dono, address gastador) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract Quita {
    // =========================================================================
    // ENDERECOS OFICIAIS - Arc Mainnet
    // =========================================================================

    /// @notice Interface ERC-20 do USDC na Arc (mesmo endereco em Mainnet e Testnet).
    address public constant USDC = 0x3600000000000000000000000000000000000000;

    /// @notice EURC na Arc Mainnet (6 decimais).
    address public constant EURC = 0xbEf5f6d51CB62b58e6A8f77868681825C6fe21c1;

    /// @notice Limite de caracteres da descricao (evita custo de gas absurdo).
    uint256 public constant LIMITE_DESCRICAO = 200;

    /// @notice Limite de caracteres do memo gravado no pagamento.
    uint256 public constant LIMITE_MEMO = 140;

    // =========================================================================
    // TIPOS
    // =========================================================================

    enum Moeda { USDC, EURC }
    enum Status { Aberta, Paga, Cancelada }

    struct Cobranca {
        uint256 id;          // numero sequencial, comeca em 1
        address recebedor;   // quem criou e quem recebe
        address pagador;     // quem pagou (endereco zero enquanto aberta)
        uint256 valor;       // sempre em 6 decimais
        Moeda   moeda;       // USDC ou EURC
        Status  status;      // Aberta / Paga / Cancelada
        string  descricao;   // "Consultoria de outubro"
        string  memo;        // mensagem do pagador, gravada on-chain
        uint256 criadaEm;    // timestamp do bloco
        uint256 pagaEm;      // timestamp do bloco (zero enquanto nao paga)
    }

    // =========================================================================
    // ARMAZENAMENTO
    // =========================================================================

    uint256 public totalCobrancas;

    mapping(uint256 => Cobranca) private _cobrancas;
    mapping(address => uint256[]) private _emitidasPor;
    mapping(address => uint256[]) private _pagasPor;

    // =========================================================================
    // EVENTOS (o frontend escuta isso para montar o historico)
    // =========================================================================

    event CobrancaCriada(
        uint256 indexed id,
        address indexed recebedor,
        uint256 valor,
        Moeda moeda,
        string descricao
    );

    event CobrancaPaga(
        uint256 indexed id,
        address indexed pagador,
        address indexed recebedor,
        uint256 valor,
        Moeda moeda,
        string memo
    );

    event CobrancaCancelada(uint256 indexed id, address indexed recebedor);

    // =========================================================================
    // PROTECAO CONTRA REENTRANCIA (escrita a mao - ver decisao 1)
    // =========================================================================

    uint256 private _trava = 1; // 1 = destravado, 2 = travado

    modifier semReentrada() {
        require(_trava == 1, "Quita: reentrada");
        _trava = 2;
        _;
        _trava = 1;
    }

    // =========================================================================
    // FUNCOES PRINCIPAIS
    // =========================================================================

    /**
     * @notice Cria uma cobranca. Quem chama vira o recebedor.
     * @param valor      Valor em 6 decimais. 10.50 USDC => 10500000
     * @param moeda      0 = USDC, 1 = EURC
     * @param descricao  Texto curto, ate 200 caracteres
     * @return id        Numero da cobranca (use no link de pagamento)
     */
    function criarCobranca(
        uint256 valor,
        Moeda moeda,
        string calldata descricao
    ) external returns (uint256 id) {
        require(valor > 0, "Quita: valor deve ser maior que zero");
        require(bytes(descricao).length <= LIMITE_DESCRICAO, "Quita: descricao muito longa");

        totalCobrancas += 1;
        id = totalCobrancas;

        Cobranca storage c = _cobrancas[id];
        c.id = id;
        c.recebedor = msg.sender;
        c.valor = valor;
        c.moeda = moeda;
        c.status = Status.Aberta;
        c.descricao = descricao;
        c.criadaEm = block.timestamp;

        _emitidasPor[msg.sender].push(id);

        emit CobrancaCriada(id, msg.sender, valor, moeda, descricao);
    }

    /**
     * @notice Paga uma cobranca aberta. Exige approve previo no token.
     * @param id    Numero da cobranca
     * @param memo  Mensagem gravada on-chain junto ao pagamento (ate 140 chars)
     *
     * O dinheiro sai do pagador e cai no recebedor na mesma transacao.
     * O contrato nao fica com nada em momento algum.
     */
    function pagar(uint256 id, string calldata memo) external semReentrada {
        Cobranca storage c = _cobrancas[id];

        require(c.id != 0, "Quita: cobranca inexistente");
        require(c.status == Status.Aberta, "Quita: cobranca nao esta aberta");
        require(msg.sender != c.recebedor, "Quita: nao pode pagar a si mesmo");
        require(bytes(memo).length <= LIMITE_MEMO, "Quita: memo muito longo");

        // Efeitos antes da interacao (padrao checks-effects-interactions).
        c.status = Status.Paga;
        c.pagador = msg.sender;
        c.pagaEm = block.timestamp;
        c.memo = memo;

        _pagasPor[msg.sender].push(id);

        _transferirDe(enderecoDoToken(c.moeda), msg.sender, c.recebedor, c.valor);

        emit CobrancaPaga(id, msg.sender, c.recebedor, c.valor, c.moeda, memo);
    }

    /**
     * @notice Cancela uma cobranca ainda aberta. So o recebedor pode.
     */
    function cancelar(uint256 id) external {
        Cobranca storage c = _cobrancas[id];

        require(c.id != 0, "Quita: cobranca inexistente");
        require(msg.sender == c.recebedor, "Quita: apenas o recebedor cancela");
        require(c.status == Status.Aberta, "Quita: cobranca nao esta aberta");

        c.status = Status.Cancelada;

        emit CobrancaCancelada(id, c.recebedor);
    }

    // =========================================================================
    // CONSULTAS (nao gastam gas quando chamadas pelo frontend)
    // =========================================================================

    /// @notice Retorna a cobranca inteira.
    function consultar(uint256 id) external view returns (Cobranca memory) {
        require(_cobrancas[id].id != 0, "Quita: cobranca inexistente");
        return _cobrancas[id];
    }

    /**
     * @notice Diz ANTES da transacao se o pagamento vai passar, e por que nao.
     * @dev    O frontend usa isso para avisar o usuario em vez de deixar
     *         a transacao falhar na cara dele. Detalhe de UX que importa.
     * @return ok      true se da para pagar agora
     * @return motivo  texto explicando o que falta
     */
    function podePagar(uint256 id, address pagador)
        external
        view
        returns (bool ok, string memory motivo)
    {
        Cobranca storage c = _cobrancas[id];

        if (c.id == 0) return (false, "Cobranca inexistente");
        if (c.status == Status.Paga) return (false, "Cobranca ja foi paga");
        if (c.status == Status.Cancelada) return (false, "Cobranca cancelada");
        if (pagador == c.recebedor) return (false, "Voce nao pode pagar a si mesmo");

        IERC20 token = IERC20(enderecoDoToken(c.moeda));

        if (token.balanceOf(pagador) < c.valor) {
            return (false, "Saldo insuficiente");
        }
        if (token.allowance(pagador, address(this)) < c.valor) {
            return (false, "Falta aprovar o token (approve)");
        }

        return (true, "Pronto para pagar");
    }

    /// @notice IDs das cobrancas criadas por um endereco.
    function cobrancasEmitidas(address de) external view returns (uint256[] memory) {
        return _emitidasPor[de];
    }

    /// @notice IDs das cobrancas pagas por um endereco.
    function cobrancasPagas(address de) external view returns (uint256[] memory) {
        return _pagasPor[de];
    }

    /// @notice Endereco do token de uma moeda. 0 = USDC, 1 = EURC.
    function enderecoDoToken(Moeda moeda) public pure returns (address) {
        return moeda == Moeda.USDC ? USDC : EURC;
    }

    // =========================================================================
    // INTERNO
    // =========================================================================

    /**
     * @dev Chama transferFrom de forma segura.
     *      Alguns tokens ERC-20 nao retornam bool (nao seguem o padrao a risca).
     *      Este trecho aceita os dois formatos e reverte se a transferencia falhar.
     */
    function _transferirDe(address token, address de, address para, uint256 valor) private {
        (bool sucesso, bytes memory retorno) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, de, para, valor)
        );
        require(
            sucesso && (retorno.length == 0 || abi.decode(retorno, (bool))),
            "Quita: transferencia falhou (saldo ou approve)"
        );
    }
}
