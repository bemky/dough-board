import { Tooltip } from 'uniform'; 

document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('[data-tooltip]').forEach(el => {
        new Tooltip({
            anchor: el,
            content: el.dataset.tooltip
        })
    })
})