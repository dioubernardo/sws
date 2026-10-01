# Static Web Server — SWS 🐹

<p align="center">
  <img src="https://raw.githubusercontent.com/dioubernardo/sws/refs/heads/main/tests/fixtures/logo.png" width="150" alt="sws logo">
</p>

SWS é um build do Nginx otimizado para servir arquivos estáticos com o mínimo possível de complexidade, dependências e consumo de recursos.

O objetivo do SWS é fazer uma única coisa bem:

> Entregar arquivos estáticos a partir de `/www`

O SWS não pretende ser um servidor web de propósito geral.

Se o seu projeto precisar de recursos como proxy reverso, reescrita de URL (rewrite) complexa, autenticação, balanceamento de carga, múltiplos upstreams ou outras configurações avançadas típicas de um servidor completo, utilize a imagem padrão do Nginx ou o Apache.

## Princípios

* Simplicidade acima de funcionalidades.
* Baixo consumo de recursos.
* Container pequeno e leve.
* Inicialização rápida.
* Configuração mínima (quase zero).
* Adequado para execução atrás de um proxy reverso, como o Traefik.
* Nenhuma funcionalidade será adicionada sem uma justificativa clara e alinhada ao objetivo principal do projeto.

## Como utilizar

```yaml
services:
  site:
    image: bersil/sws:main
    restart: unless-stopped
    volumes:
      - ./html-files:/www
    tmpfs:
      - /var/cache/nginx
      - /var/run
      - /tmp
```

## Comportamento

### `document_root`

**Não é configurável**; o caminho é fixo em `/www`.

Caminhos inexistentes retornam `404 Not Found`, exceto quando `SWS_SPA_FALLBACK=1`. Nesse caso, o arquivo `/www/index.html` é retornado. O valor padrão de `SWS_SPA_FALLBACK` é `0`.

### Cache de processamento

O Nginx está configurado para manter na memória as informações de até 1.000 arquivos e erros de acesso frequentes, revalidando-os a cada 60 segundos e descartando os itens inativos após 60 segundos se não tiverem ao menos 2 acessos.

### Cache HTTP

O comportamento do cache HTTP é controlado pela variável `SWS_CACHE_POLICY`. Os valores possíveis são `max-age`, `immutable` e `no-cache`. O valor padrão é `max-age`.

O arquivo `/www/index.html` é tratado como **exceção** e **sempre** utilizará `Cache-Control: no-cache`. Isso garante que aplicações recebam a versão mais atualizada do documento HTML de entrada, enquanto os demais arquivos utilizam políticas de cache mais agressivas.

* **`SWS_CACHE_POLICY=no-cache`**: O cliente pode armazenar a resposta, mas deve revalidá-la com o servidor antes de reutilizá-la. O SWS utiliza os cabeçalhos `ETag` e `Last-Modified` para permitir respostas `304 Not Modified`.
* **`SWS_CACHE_POLICY=max-age`**: O cliente pode reutilizar a resposta durante o período definido por `SWS_MAX_AGE=`. O valor padrão é `86400` (24 horas).
* **`SWS_CACHE_POLICY=immutable`**: A resposta é considerada imutável pelo cliente, retornando `Cache-Control: public, max-age=31536000, immutable`. Essa política é destinada principalmente a arquivos que possuem o hash de versão no próprio nome (ex.: `app.a83f92.js` ou `style.19c2a1.css`).

### Compressão

Quando a requisição indicar suporte, o conteúdo será comprimido utilizando o algoritmo suportado pelo cliente, preferencialmente **Brotli** ou **Gzip**. O projeto considera apenas navegadores modernos.

### Logs

Os logs de requisições HTTP utilizam o formato `IP DATA "METHOD PATH PROTOCOL" HTTP_CODE BYTES` e são registrados **apenas para respostas 4xx e 5xx**. O endereço IP é obtido do cabeçalho `X-Forwarded-For`; quando ausente, o `Remote addr` é utilizado.

### Health check

O endpoint `/_health` sempre retorna `200 OK`.

## Como compilar e rodar a partir do código-fonte

```bash
docker build -t sws .
```

## Para rodar os testes

```bash
bash tests/tests.sh
```

## Envindo a imagem para Docker Hub

```bash
docker build -t bersil/sws:main .
docker push bersil/sws:main
```

# @TODO

- Comprimir os arquivos antes e usar --with-http_gzip_static_module