import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ProblemFilter } from './api/problem.filter';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { logger: ['error', 'warn', 'log'] });
  app.useGlobalFilters(new ProblemFilter());
  await app.listen(Number(process.env.PORT ?? 3001));
}

void bootstrap();
