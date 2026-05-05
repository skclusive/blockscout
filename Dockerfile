# *****************************
# *** STAGE 1: Dependencies ***
# *****************************
FROM node:22.14.0-alpine AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat python3 make g++
RUN ln -sf /usr/bin/python3 /usr/bin/python
RUN corepack enable && corepack prepare pnpm@10.32.1 --activate

### Install all workspace dependencies in one place
WORKDIR /app
RUN apk add git
COPY . .
RUN pnpm install --frozen-lockfile


# *****************************
# ****** STAGE 2: Build *******
# *****************************
FROM node:22.14.0-alpine AS builder
RUN apk add --no-cache --upgrade libc6-compat bash jq dos2unix
RUN corepack enable && corepack prepare pnpm@10.32.1 --activate

# pass build args to env variables
ARG GIT_COMMIT_SHA
ENV NEXT_PUBLIC_GIT_COMMIT_SHA=$GIT_COMMIT_SHA
ARG GIT_TAG
ENV NEXT_PUBLIC_GIT_TAG=$GIT_TAG
ARG NEXT_OPEN_TELEMETRY_ENABLED
ENV NEXT_OPEN_TELEMETRY_ENABLED=$NEXT_OPEN_TELEMETRY_ENABLED

ARG API_BASE_PATH
RUN echo "API_BASE_PATH $API_BASE_PATH"
ENV NEXT_PUBLIC_API_BASE_PATH=$API_BASE_PATH

ENV NODE_ENV production

### APP
# Copy dependencies and source code from deps stage
WORKDIR /app
COPY --from=deps /app ./

RUN dos2unix deploy/scripts/build_sprite.sh && \
    dos2unix deploy/scripts/collect_envs.sh
# Build SVG sprite and generate .env.registry with ENVs list and save build args into .env file
RUN set -a && \
    source ./deploy/scripts/build_sprite.sh && \
    ./deploy/scripts/collect_envs.sh ./docs/ENVS.md && \
    set +a

# Next.js collects completely anonymous telemetry data about general usage.
# Learn more here: https://nextjs.org/telemetry
# Uncomment the following line in case you want to disable telemetry during the build.
# ENV NEXT_TELEMETRY_DISABLED 1

# Build app for production
ENV NODE_OPTIONS="--max-old-space-size=8192"
RUN pnpm routes:generate
RUN pnpm run build


### FEATURE REPORTER
RUN cd ./deploy/tools/feature-reporter && pnpm run build


### ENV VARIABLES CHECKER
RUN cd ./deploy/tools/envs-validator && pnpm run build


### FAVICON GENERATOR
# Portable bundle for the runtime image (self-contained node_modules)
RUN pnpm --filter favicon-generator deploy --prod /app/favicon-generator-bundle

### SITEMAP GENERATOR
RUN pnpm --filter sitemap-generator deploy --prod /app/sitemap-generator-bundle

### MULTICHAIN CONFIG GENERATOR
RUN cd ./deploy/tools/multichain-config-generator && pnpm run build

### ESSENTIAL DAPPS CHAINS CONFIG GENERATOR
RUN cd ./deploy/tools/essential-dapps-chains-config-generator && pnpm run build

### llms.txt GENERATOR
RUN cd ./deploy/tools/llms-txt-generator && pnpm run build


# *****************************
# ******* STAGE 3: Run ********
# *****************************
# Production image, copy all the files and run next
FROM node:22.14.0-alpine AS runner
RUN apk add --no-cache --upgrade bash curl jq unzip dos2unix

### APP
WORKDIR /app

# Uncomment the following line in case you want to disable telemetry during runtime.
# ENV NEXT_TELEMETRY_DISABLED 1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Set the correct permission for prerender cache
RUN mkdir .next
RUN chown nextjs:nodejs .next

COPY --from=builder /app/next.config.js ./
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./package.json

# Copy tools
COPY --from=builder /app/deploy/tools/envs-validator/dist/index.js ./envs-validator/index.js
COPY --from=builder /app/deploy/tools/feature-reporter/dist/index.js ./feature-reporter.js
COPY --from=builder /app/deploy/tools/multichain-config-generator/dist ./deploy/tools/multichain-config-generator/dist
COPY --from=builder /app/deploy/tools/llms-txt-generator/dist ./deploy/tools/llms-txt-generator/dist
COPY --from=builder /app/deploy/tools/essential-dapps-chains-config-generator/dist ./deploy/tools/essential-dapps-chains-config-generator/dist

# Copy scripts
## Entrypoint
COPY --chmod=755 ./deploy/scripts/entrypoint.sh .
## ENV validator and client script maker
COPY --chmod=755 ./deploy/scripts/validate_envs.sh .
COPY --chmod=755 ./deploy/scripts/make_envs_script.sh .
## Assets downloader
COPY --chmod=755 ./deploy/scripts/download_assets.sh .
## OG image generator
COPY ./deploy/scripts/og_image_generator.js .
## Favicon generator
COPY --chmod=755 ./deploy/scripts/favicon_generator.sh .
COPY --from=builder /app/favicon-generator-bundle ./deploy/tools/favicon-generator
RUN ["chmod", "-R", "777", "./deploy/tools/favicon-generator"]
RUN ["chmod", "-R", "777", "./public"]
## Sitemap generator
COPY --chmod=755 ./deploy/scripts/sitemap_generator.sh .
COPY --from=builder /app/sitemap-generator-bundle ./deploy/tools/sitemap-generator

# Copy ENVs files
COPY --from=builder /app/.env.registry .
COPY --from=builder /app/.env .

# Copy ENVs presets
ARG ENVS_PRESET
ENV ENVS_PRESET=$ENVS_PRESET
COPY ./configs/envs ./configs/envs

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

RUN dos2unix entrypoint.sh \
    && dos2unix validate_envs.sh \
    && dos2unix make_envs_script.sh \
    && dos2unix download_assets.sh \
    && dos2unix favicon_generator.sh \
    && dos2unix sitemap_generator.sh \
    && chmod +x entrypoint.sh \
    && chmod +x validate_envs.sh \
    && chmod +x make_envs_script.sh \
    && chmod +x download_assets.sh \
    && chmod +x favicon_generator.sh \
    && chmod +x sitemap_generator.sh

ENTRYPOINT ["./entrypoint.sh"]

USER nextjs

EXPOSE 3000

ENV PORT 3000

CMD ["node", "server.js"]
