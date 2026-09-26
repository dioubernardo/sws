# Static Web Server — SWS 🐹

SWS é um build od nginx otimizado para servir arquivos estáticos com o
mínimo possível de complexidade, dependências e consumo de recursos.

O objetivo do SWS é fazer uma única coisa bem:

> Entregar arquivos estáticos de /www

SWS não pretende ser um servidor web de propósito geral.

Se o projeto precisar de funcionalidades como proxy reverso,
rewrite complexo, autenticação, balanceamento, múltiplos upstreams,
configurações avançadas ou outras funcionalidades típicas de um
servidor web completo, use Nginx ou Apache.

## Princípios

* Simplicidade acima de funcionalidades.
* Baixo consumo de recursos.
* Container pequeno.
* Inicialização rápida.
* Configuração mínima, quase zero.
* Adequado para execução atrás de um reverse proxy, como Traefik.
* Nenhuma funcionalidade será adicionada sem uma justificativa
  clara relacionada ao objetivo principal do projeto.

## Comportamento

### document_root

**Não é para ser configuravel** é fixo em `/www`.

Caminhos inexistentes irão retornar `404 Not Found`, exceto quando
`SWS_SPA_FALLBACK=1`, neste caso o `/www/index.html`
é retornado. O valor padrão de `SWS_SPA_FALLBACK` é `0`.

### Cache de processamento

O Nginx está configurado para manter na memória as informações de até 1000 arquivos e erros de acesso frequentes, revalidando-os a cada 60 segundos e descartando os itens inativos após 60 segundos se não tiverem ao menos 2 acessos.

### Cache HTTP

O comportamento do cache HTTP é controlado pela variável `SWS_CACHE_POLICY`,
os valores possíveis são: `max-age`, `immutable` e `no-cache`. Seu valor padrão é `max-age`.

O arquivo `/www/index.html` é tratado como **exceção** e **sempre** será `Cache-Control: no-cache`.
Isso permite que aplicações SPA recebam uma versão atualizada do
documento HTML de entrada, enquanto os demais arquivos podem utilizar
políticas de cache mais agressivas.

Quando `SWS_CACHE_POLICY=no-cache`, o cliente pode armazenar a resposta,
mas deve revalidá-la antes de utilizá-la novamente.
O SWS utiliza `ETag` e `Last-Modified` para permitir que a
revalidação resulte em `304 Not Modified`.

Quando `SWS_CACHE_POLICY=max-age`, o cliente pode reutilizar a resposta
durante o período definido por `SWS_MAX_AGE=<segundos>`. Seu valor padrão é
de `86400` (24 horas).

Quando `SWS_CACHE_POLICY=immutable`, a resposta é considerada imutável pelo cliente.
A resposta será `Cache-Control: public, max-age=31536000, immutable`.
Essa política é destinada principalmente a arquivos que possuem
identificação de versão no nome, como: `app.a83f92.js` ou `style.19c2a1.css`.

### Compressão

Quando a requisição indicar suporte, o conteúdo será comprimido utilizando um
algoritmo suportado pelo cliente, preferencialmente Brotli ou gzip.
O projeto considera apenas navegadores modernos.

### Logs

Os logs de requisições HTTP utilizam o formato `IP DATA "METHOD PATH PROTOCOL" HTTP_CODE BYTES`, sendo registrados apenas para respostas 4xx e 5xx.
O endereço IP é obtido do header `X-Forwarded-For`; quando ausente, é utilizado `Remote addr`.

### Health check

O endpoint `/_health` sempre retorna `200 OK`.

## Para compilar e rodar apartir do código fonte

```bash
docker build -t sws .
```

```bash
docker run --rm -p 3000:3000 -e "SWS_SPA_FALLBACK=1" sws
```

## Para rodar os testes

```bash
bash tests/tests.sh
```
