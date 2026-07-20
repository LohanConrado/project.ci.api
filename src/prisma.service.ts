import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { PrismaClient } from './generated/prisma/client'; 
import { PrismaPg } from '@prisma/adapter-pg';

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(PrismaService.name);
  private readonly MAX_RETRIES = 10;
  private readonly RETRY_DELAY_MS = 3000;

  constructor() {
    const connectionString = process.env.DATABASE_URL;

    if (!connectionString) {
      throw new Error('DATABASE_URL is not defined');
    }

    const adapter = new PrismaPg(connectionString);
    super({ adapter });
  }

  async onModuleInit() {
    await this.connectWithRetry();
  }

  private async connectWithRetry(attempt = 1): Promise<void> {
    this.logger.log('Conectando ao banco ...');

    try {
      await this.$connect();
      this.logger.log('Sucesso, aplicação conectada ao banco.');
    } catch (error) {
      if (attempt >= this.MAX_RETRIES) {
        this.logger.error(
          `Falha ao conectar ao banco após ${this.MAX_RETRIES} tentativas.`,
          error,
        );

        throw error;
      }
      this.logger.warn(
        `Sem sucesso, tentando novamente (${attempt}/${this.MAX_RETRIES})...`,
      );

      await this.delay(this.RETRY_DELAY_MS);
      return this.connectWithRetry(attempt + 1);
    }
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
