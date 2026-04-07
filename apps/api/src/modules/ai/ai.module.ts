import { Module } from '@nestjs/common';
import { AiProvider } from './ai-provider.abstract';
import { GeminiProvider } from './services/gemini.provider';
import { OllamaProvider } from './services/ollama.provider';
import { VllmProvider } from './services/vllm.provider';
import { QdrantService } from './services/qdrant.service';
import { QdrantInitService } from './services/qdrant-init.service';
import { IntentExtractorService } from './services/intent-extractor.service';
import { AiController } from './ai.controller';
import { AuthModule } from '../auth/auth.module';

function createAiProvider(): AiProvider {
  const provider = process.env['AI_PROVIDER'] ?? 'gemini';
  switch (provider) {
    case 'ollama':
      return new OllamaProvider();
    case 'vllm':
      return new VllmProvider();
    default:
      return new GeminiProvider();
  }
}

@Module({
  imports: [AuthModule],
  controllers: [AiController],
  providers: [
    {
      provide: AiProvider,
      useFactory: createAiProvider,
    },
    QdrantService,
    QdrantInitService,
    IntentExtractorService,
  ],
  exports: [AiProvider, IntentExtractorService, QdrantService],
})
export class AiModule {}
