import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  const port = Number(process.env.PORT ?? 3000);

  await app.listen(port, '0.0.0.0');

  const url = await app.getUrl();

  console.log(`Rodando em: ${url}`);
}

bootstrap();
