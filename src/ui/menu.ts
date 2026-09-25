// O menu do sistema: um lugar só, igual em todas as telas.
import {
  Building2,
  CalendarDays,
  ChartColumn,
  CircleUser,
  ClipboardCheck,
  FileQuestionMark,
  FolderLock,
  Gauge,
  Gift,
  House,
  ListChecks,
  Lock,
  Medal,
  Megaphone,
  MessageSquare,
  MonitorPlay,
  Receipt,
  Settings,
  Store,
  Target,
  Trophy,
  UserPlus,
  Users,
  Wrench,
  type LucideIcon,
} from "lucide-react";

export type ItemMenu = { to: string; label: string; icone: LucideIcon };
export type GrupoMenu = { titulo: string; itens: ItemMenu[] };

export const MENU_MASTER: GrupoMenu[] = [
  { titulo: "Início", itens: [{ to: "/inicio", label: "Início", icone: House }] },
  {
    titulo: "Operação",
    itens: [
      { to: "/operacional", label: "Painel da loja", icone: MonitorPlay },
      { to: "/painel", label: "Quadro", icone: ClipboardCheck },
      { to: "/tarefas", label: "Tarefas", icone: ListChecks },
      { to: "/solicitacoes", label: "Solicitações", icone: Wrench },
      { to: "/relatorios", label: "Relatórios", icone: ChartColumn },
    ],
  },
  {
    titulo: "Pessoas",
    itens: [
      { to: "/funcionarios", label: "Equipe", icone: Users },
      { to: "/feedbacks", label: "Feedbacks", icone: MessageSquare },
      { to: "/justificativas", label: "Justificativas", icone: FileQuestionMark },
    ],
  },
  {
    titulo: "Gamificação",
    itens: [
      { to: "/ranking", label: "Ranking", icone: Trophy },
      { to: "/conquistas", label: "Conquistas", icone: Medal },
      { to: "/premios", label: "Prêmios", icone: Gift },
      { to: "/extrato", label: "Extrato", icone: Receipt },
    ],
  },
  { titulo: "Metas", itens: [{ to: "/metas", label: "Metas", icone: Target }] },
  { titulo: "Agenda", itens: [{ to: "/agenda", label: "Agenda", icone: CalendarDays }] },
  {
    titulo: "RH",
    itens: [
      { to: "/comunicados", label: "Comunicados", icone: Megaphone },
      { to: "/documentos-pessoais", label: "Documentos pessoais", icone: FolderLock },
      { to: "/onboarding", label: "Onboarding", icone: UserPlus },
      { to: "/canal-confidencial", label: "Canal confidencial", icone: Lock },
    ],
  },
  {
    titulo: "Configurações",
    itens: [
      { to: "/gestao", label: "Lojas e links da TV", icone: Store },
      { to: "/configuracoes", label: "Configurações", icone: Settings },
      { to: "/perfil", label: "Meu perfil", icone: CircleUser },
      // Só aparece para o dono da conta (este menu é o do master). Serve para
      // chegar em /medir SEM recarregar a página, senão a medição se perde.
      { to: "/medir", label: "Medir desempenho", icone: Gauge },
    ],
  },
];

/** Barra inferior do celular (o quinto botão, "Mais", abre o menu completo). */
export const BARRA_CELULAR: ItemMenu[] = [
  { to: "/inicio", label: "Início", icone: House },
  { to: "/painel", label: "Quadro", icone: ClipboardCheck },
  { to: "/funcionarios", label: "Equipe", icone: Users },
  { to: "/metas", label: "Metas", icone: Target },
];

export const MENU_ADMIN: GrupoMenu[] = [
  { titulo: "Administração", itens: [{ to: "/admin", label: "Clientes", icone: Building2 }] },
  { titulo: "Conta", itens: [{ to: "/admin/perfil", label: "Meu perfil", icone: CircleUser }] },
];

export const BARRA_CELULAR_ADMIN: ItemMenu[] = [
  { to: "/admin", label: "Clientes", icone: Building2 },
  { to: "/admin/perfil", label: "Meu perfil", icone: CircleUser },
];
