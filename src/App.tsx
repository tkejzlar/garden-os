import { lazy, Suspense } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AppShell } from './components/AppShell'
import { Loader2 } from 'lucide-react'

// Lazy load pages for code splitting
const Dashboard = lazy(() => import('./pages/Dashboard').then(m => ({ default: m.Dashboard })))
const PlantsList = lazy(() => import('./pages/PlantsList').then(m => ({ default: m.PlantsList })))
const PlantDetail = lazy(() => import('./pages/PlantDetail').then(m => ({ default: m.PlantDetail })))
const SeedsList = lazy(() => import('./pages/SeedsList').then(m => ({ default: m.SeedsList })))
const SeedForm = lazy(() => import('./pages/SeedForm').then(m => ({ default: m.SeedForm })))
const PlanHub = lazy(() => import('./pages/PlanHub').then(m => ({ default: m.PlanHub })))
const GardenDesigner = lazy(() => import('./pages/GardenDesigner').then(m => ({ default: m.GardenDesigner })))
const Settings = lazy(() => import('./pages/Settings').then(m => ({ default: m.Settings })))
const CompanionsPage = lazy(() => import('./pages/CompanionsPage').then(m => ({ default: m.CompanionsPage })))

function PageLoader() {
  return (
    <div className="flex items-center justify-center py-20">
      <Loader2 className="w-6 h-6 animate-spin text-[var(--color-primary)]" />
    </div>
  )
}

export function App() {
  return (
    <BrowserRouter>
      <AppShell>
        <Suspense fallback={<PageLoader />}>
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/garden" element={<GardenDesigner />} />
            <Route path="/plants" element={<PlantsList />} />
            <Route path="/plants/:id" element={<PlantDetail />} />
            <Route path="/seeds" element={<SeedsList />} />
            <Route path="/seeds/new" element={<SeedForm />} />
            <Route path="/seeds/:id" element={<SeedForm />} />
            <Route path="/plan" element={<PlanHub />} />
            <Route path="/settings" element={<Settings />} />
            <Route path="/companions" element={<CompanionsPage />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Suspense>
      </AppShell>
    </BrowserRouter>
  )
}
