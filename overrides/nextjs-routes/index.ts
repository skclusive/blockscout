import type { Route } from 'nextjs-routes';
import { route as typedRoute } from 'nextjs-routes';

import config from 'configs/app';

export function route(r: Route): string {
  const url = typedRoute(r);
  const basePath = config.apis.general?.basePath ?? '';
  return url.startsWith(basePath) ?
    url :
    `${ config.apis.general?.basePath ?? '' }/${ url }`.replaceAll('//', '/');
}
