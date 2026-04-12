import type IORedis from 'ioredis'
import jwt from 'jsonwebtoken'
import type { Socket } from 'socket.io'

interface SocketJwtPayload {
  sub: string
  jti: string
}

function extractToken(socket: Socket): string | null {
  const authToken = socket.handshake.auth.token
  if (typeof authToken === 'string' && authToken.trim().length > 0) {
    return authToken
  }

  const authorization = socket.handshake.headers.authorization
  if (typeof authorization === 'string' && authorization.startsWith('Bearer ')) {
    return authorization.slice(7)
  }

  return null
}

export async function authenticateSocketSession(
  socket: Socket,
  stateRedis: IORedis,
  jwtPrivateKey: string,
  jwtPublicKey: string,
  isProduction: boolean,
): Promise<SocketJwtPayload> {
  const token = extractToken(socket)
  if (!token) {
    throw new Error('Authentication required')
  }

  const signingKey = isProduction ? jwtPublicKey : jwtPrivateKey
  if (!signingKey) {
    throw new Error('JWT signing key not configured')
  }

  const algorithm = isProduction ? 'RS256' : 'HS256'
  const decoded = jwt.verify(token, signingKey, {
    algorithms: [algorithm],
  }) as SocketJwtPayload

  const sessionExists = await stateRedis.exists(
    `session:${decoded.sub}:${decoded.jti}`,
  )

  if (!sessionExists) {
    throw new Error('Session revoked')
  }

  socket.data.userId = decoded.sub
  socket.data.jti = decoded.jti

  return decoded
}
